#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER1_USER_ID="seller_user_003_${CASE_SUFFIX}"
SELLER2_USER_ID="seller_user_004_${CASE_SUFFIX}"
BUYER_USER_ID="buyer_user_multi_${CASE_SUFFIX}"
SELLER1_ID="seller_003_${CASE_SUFFIX}"
SELLER2_ID="seller_004_${CASE_SUFFIX}"
ORDER1_ID="order_300_${CASE_SUFFIX}"
ORDER2_ID="order_301_${CASE_SUFFIX}"
ORDER_ITEM1_ID="order_item_300_${CASE_SUFFIX}"
ORDER_ITEM2_ID="order_item_301_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/payout_multiple_sellers_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/payout_multiple_sellers_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given — create two sellers and two completed unpaid orders in the same payout run
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${SELLER1_USER_ID}', 'seller-003-${CASE_SUFFIX}@example.com', 'codevalid', 'SELLER', 'ACTIVE'),
  ('${SELLER2_USER_ID}', 'seller-004-${CASE_SUFFIX}@example.com', 'codevalid', 'SELLER', 'ACTIVE'),
  ('${BUYER_USER_ID}', 'buyer-multi-${CASE_SUFFIX}@example.com', 'codevalid', 'BUYER', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO sellers (id, user_id, store_name, stripe_account_id, status)
VALUES
  ('${SELLER1_ID}', '${SELLER1_USER_ID}', 'Multi Seller 003 ${CASE_SUFFIX}', 'acct_stripe_ghi789', 'ACTIVE'),
  ('${SELLER2_ID}', '${SELLER2_USER_ID}', 'Multi Seller 004 ${CASE_SUFFIX}', 'acct_stripe_jkl012', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO orders (id, buyer_id, total_cents, platform_fee_cents, status, payout_status, created_at, updated_at)
VALUES
  ('${ORDER1_ID}', '${BUYER_USER_ID}', 20000, 2000, 'COMPLETED', 'UNPAID', NOW(), NOW()),
  ('${ORDER2_ID}', '${BUYER_USER_ID}', 15000, 1500, 'COMPLETED', 'UNPAID', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO order_items (id, order_id, seller_id, qty, price_at_purchase, seller_payout_cents)
VALUES
  ('${ORDER_ITEM1_ID}', '${ORDER1_ID}', '${SELLER1_ID}', 1, 20000, 18000),
  ('${ORDER_ITEM2_ID}', '${ORDER2_ID}', '${SELLER2_ID}', 1, 15000, 13500)
ON CONFLICT (id) DO NOTHING;
SQL

# When — run weekly payouts
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" > "$STATUS_FILE"

# Then — both sellers are paid, and net amounts are $180.00 and $135.00 after the 10% fee
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]

grep -E '18000|13500|180(\.00)?|135(\.00)?|seller-003|seller-004|success|paid' "$RESPONSE_FILE" >/dev/null || true

ORDER1_PAYOUT_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT COALESCE(payout_status, '') FROM orders WHERE id = '${ORDER1_ID}';")"
ORDER2_PAYOUT_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT COALESCE(payout_status, '') FROM orders WHERE id = '${ORDER2_ID}';")"
[ "$ORDER1_PAYOUT_STATUS" = "PAID" ]
[ "$ORDER2_PAYOUT_STATUS" = "PAID" ]

SELLER1_TOTAL="$(psql "$DATABASE_URL" -t -A -c "SELECT COALESCE(SUM(amount_cents),0) FROM payouts WHERE seller_id = '${SELLER1_ID}';" 2>/dev/null || printf '0')"
SELLER2_TOTAL="$(psql "$DATABASE_URL" -t -A -c "SELECT COALESCE(SUM(amount_cents),0) FROM payouts WHERE seller_id = '${SELLER2_ID}';" 2>/dev/null || printf '0')"
[ "$SELLER1_TOTAL" = "18000" ]
[ "$SELLER2_TOTAL" = "13500" ]

echo "CODEVALID_TEST_ASSERTION_OK:payout_multiple_sellers"

# Cleanup — remove payouts and all seeded rows for both sellers
psql "$DATABASE_URL" <<SQL
DELETE FROM payouts WHERE seller_id IN ('${SELLER1_ID}', '${SELLER2_ID}') OR order_id IN ('${ORDER1_ID}', '${ORDER2_ID}');
DELETE FROM order_items WHERE id IN ('${ORDER_ITEM1_ID}', '${ORDER_ITEM2_ID}') OR order_id IN ('${ORDER1_ID}', '${ORDER2_ID}');
DELETE FROM orders WHERE id IN ('${ORDER1_ID}', '${ORDER2_ID}');
DELETE FROM sellers WHERE id IN ('${SELLER1_ID}', '${SELLER2_ID}');
DELETE FROM users WHERE id IN ('${SELLER1_USER_ID}', '${SELLER2_USER_ID}', '${BUYER_USER_ID}');
SQL
