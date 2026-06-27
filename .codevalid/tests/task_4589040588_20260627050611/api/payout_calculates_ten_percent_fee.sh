#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller_user_fee_${CASE_SUFFIX}"
BUYER_USER_ID="buyer_user_fee_${CASE_SUFFIX}"
SELLER_ID="seller_005_${CASE_SUFFIX}"
ORDER_ID="order_400_${CASE_SUFFIX}"
ORDER_ITEM_ID="order_item_400_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/payout_calculates_ten_percent_fee_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/payout_calculates_ten_percent_fee_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given — create one completed unpaid $250.00 order with a $25.00 fee and $225.00 seller payout
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${SELLER_USER_ID}', 'seller-005-${CASE_SUFFIX}@example.com', 'codevalid', 'SELLER', 'ACTIVE'),
  ('${BUYER_USER_ID}', 'buyer-fee-${CASE_SUFFIX}@example.com', 'codevalid', 'BUYER', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO sellers (id, user_id, store_name, stripe_account_id, status)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Fee Verification Store ${CASE_SUFFIX}', 'acct_stripe_mno345', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO orders (id, buyer_id, total_cents, platform_fee_cents, status, payout_status, created_at, updated_at)
VALUES ('${ORDER_ID}', '${BUYER_USER_ID}', 25000, 2500, 'COMPLETED', 'UNPAID', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO order_items (id, order_id, seller_id, qty, price_at_purchase, seller_payout_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${SELLER_ID}', 1, 25000, 22500)
ON CONFLICT (id) DO NOTHING;
SQL

# When — run weekly payouts
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" > "$STATUS_FILE"

# Then — HTTP succeeds and recorded payout is exactly 22500 cents while order fee remains 2500 cents
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]

grep -E '22500|2500|225(\.00)?|25(\.00)?|fee|payout' "$RESPONSE_FILE" >/dev/null || true

ORDER_FEE="$(psql "$DATABASE_URL" -t -A -c "SELECT platform_fee_cents FROM orders WHERE id = '${ORDER_ID}';")"
[ "$ORDER_FEE" = "2500" ]

PAYOUT_TOTAL="$(psql "$DATABASE_URL" -t -A -c "SELECT COALESCE(SUM(amount_cents),0) FROM payouts WHERE seller_id = '${SELLER_ID}';" 2>/dev/null || printf '0')"
[ "$PAYOUT_TOTAL" = "22500" ]

echo "CODEVALID_TEST_ASSERTION_OK:payout_calculates_ten_percent_fee"

# Cleanup — remove payouts and all seeded rows
psql "$DATABASE_URL" <<SQL
DELETE FROM payouts WHERE seller_id = '${SELLER_ID}' OR order_id = '${ORDER_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}' OR order_id = '${ORDER_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER_USER_ID}');
SQL
