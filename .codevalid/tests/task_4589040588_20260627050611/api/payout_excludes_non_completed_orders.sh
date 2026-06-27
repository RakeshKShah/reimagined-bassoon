#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller_user_excluded_${CASE_SUFFIX}"
BUYER_USER_ID="buyer_user_excluded_${CASE_SUFFIX}"
SELLER_ID="seller_002_${CASE_SUFFIX}"
ORDER_PENDING_ID="order_200_${CASE_SUFFIX}"
ORDER_CANCELLED_ID="order_201_${CASE_SUFFIX}"
ORDER_ITEM_PENDING_ID="order_item_200_${CASE_SUFFIX}"
ORDER_ITEM_CANCELLED_ID="order_item_201_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/payout_excludes_non_completed_orders_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/payout_excludes_non_completed_orders_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given — create seller with only pending and cancelled orders, both unpaid
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${SELLER_USER_ID}', 'seller-002-${CASE_SUFFIX}@example.com', 'codevalid', 'SELLER', 'ACTIVE'),
  ('${BUYER_USER_ID}', 'buyer-excluded-${CASE_SUFFIX}@example.com', 'codevalid', 'BUYER', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO sellers (id, user_id, store_name, stripe_account_id, status)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Excluded Orders Store ${CASE_SUFFIX}', 'acct_stripe_def456', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO orders (id, buyer_id, total_cents, platform_fee_cents, status, payout_status, created_at, updated_at)
VALUES
  ('${ORDER_PENDING_ID}', '${BUYER_USER_ID}', 5000, 500, 'PENDING', 'UNPAID', NOW(), NOW()),
  ('${ORDER_CANCELLED_ID}', '${BUYER_USER_ID}', 7500, 750, 'CANCELLED', 'UNPAID', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO order_items (id, order_id, seller_id, qty, price_at_purchase, seller_payout_cents)
VALUES
  ('${ORDER_ITEM_PENDING_ID}', '${ORDER_PENDING_ID}', '${SELLER_ID}', 1, 5000, 4500),
  ('${ORDER_ITEM_CANCELLED_ID}', '${ORDER_CANCELLED_ID}', '${SELLER_ID}', 1, 7500, 6750)
ON CONFLICT (id) DO NOTHING;
SQL

# When — run weekly payouts
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" > "$STATUS_FILE"

# Then — HTTP succeeds, no payout is created for this seller, and both orders remain unpaid
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]

grep -E '0|none|empty|\[\]' "$RESPONSE_FILE" >/dev/null || true

PENDING_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT COALESCE(payout_status, '') FROM orders WHERE id = '${ORDER_PENDING_ID}';")"
CANCELLED_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT COALESCE(payout_status, '') FROM orders WHERE id = '${ORDER_CANCELLED_ID}';")"
[ "$PENDING_STATUS" = "UNPAID" ]
[ "$CANCELLED_STATUS" = "UNPAID" ]

PAYOUT_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM payouts WHERE seller_id = '${SELLER_ID}';" 2>/dev/null || printf '0')"
[ "$PAYOUT_COUNT" = "0" ]

echo "CODEVALID_TEST_ASSERTION_OK:payout_excludes_non_completed_orders"

# Cleanup — remove seeded rows
psql "$DATABASE_URL" <<SQL
DELETE FROM payouts WHERE seller_id = '${SELLER_ID}' OR order_id IN ('${ORDER_PENDING_ID}', '${ORDER_CANCELLED_ID}');
DELETE FROM order_items WHERE id IN ('${ORDER_ITEM_PENDING_ID}', '${ORDER_ITEM_CANCELLED_ID}') OR order_id IN ('${ORDER_PENDING_ID}', '${ORDER_CANCELLED_ID}');
DELETE FROM orders WHERE id IN ('${ORDER_PENDING_ID}', '${ORDER_CANCELLED_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER_USER_ID}');
SQL
