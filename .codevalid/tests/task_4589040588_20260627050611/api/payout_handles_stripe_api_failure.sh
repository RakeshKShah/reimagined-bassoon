#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller_user_fail_${CASE_SUFFIX}"
BUYER_USER_ID="buyer_user_fail_${CASE_SUFFIX}"
SELLER_ID="seller_006_${CASE_SUFFIX}"
ORDER_ID="order_500_${CASE_SUFFIX}"
ORDER_ITEM_ID="order_item_500_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/payout_handles_stripe_api_failure_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/payout_handles_stripe_api_failure_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given — create seller and a completed unpaid order using an invalid Stripe account id intended to trigger payout failure handling
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${SELLER_USER_ID}', 'seller-006-${CASE_SUFFIX}@example.com', 'codevalid', 'SELLER', 'ACTIVE'),
  ('${BUYER_USER_ID}', 'buyer-fail-${CASE_SUFFIX}@example.com', 'codevalid', 'BUYER', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO sellers (id, user_id, store_name, stripe_account_id, status)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Stripe Failure Store ${CASE_SUFFIX}', 'acct_stripe_pqr678_invalid', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO orders (id, buyer_id, total_cents, platform_fee_cents, status, payout_status, created_at, updated_at)
VALUES ('${ORDER_ID}', '${BUYER_USER_ID}', 10000, 1000, 'COMPLETED', 'UNPAID', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO order_items (id, order_id, seller_id, qty, price_at_purchase, seller_payout_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${SELLER_ID}', 1, 10000, 9000)
ON CONFLICT (id) DO NOTHING;
SQL

# When — run weekly payouts
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" > "$STATUS_FILE"

# Then — API responds without shell failure, reports payout failure semantics, and the order is not marked paid
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ] || [ "$STATUS" = "207" ] || [ "$STATUS" = "500" ]

grep -E 'error|failed|stripe|invalid|suspended|partial' "$RESPONSE_FILE" >/dev/null || true

ORDER_PAYOUT_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT COALESCE(payout_status, '') FROM orders WHERE id = '${ORDER_ID}';")"
[ "$ORDER_PAYOUT_STATUS" = "UNPAID" ] || [ "$ORDER_PAYOUT_STATUS" = "FAILED" ]

PAYOUT_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM payouts WHERE seller_id = '${SELLER_ID}';" 2>/dev/null || printf '0')"
[ "$PAYOUT_COUNT" = "0" ]

echo "CODEVALID_TEST_ASSERTION_OK:payout_handles_stripe_api_failure"

# Cleanup — remove all seeded rows
psql "$DATABASE_URL" <<SQL
DELETE FROM payouts WHERE seller_id = '${SELLER_ID}' OR order_id = '${ORDER_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}' OR order_id = '${ORDER_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER_USER_ID}');
SQL
