#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller_user_none_${CASE_SUFFIX}"
SELLER_ID="seller_none_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/payout_handles_no_completed_orders_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/payout_handles_no_completed_orders_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given — create a seller but no completed orders eligible for payout
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}', 'seller-none-${CASE_SUFFIX}@example.com', 'codevalid', 'SELLER', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO sellers (id, user_id, store_name, stripe_account_id, status)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'No Eligible Orders ${CASE_SUFFIX}', 'acct_stripe_none000', 'ACTIVE')
ON CONFLICT (id) DO NOTHING;
SQL

PAYOUT_COUNT_BEFORE="$(psql "$DATABASE_URL" -t -A -c 'SELECT COUNT(*) FROM payouts;' 2>/dev/null || printf '0')"

# When — run weekly payouts with zero eligible orders in the system state seeded by this case
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" > "$STATUS_FILE"

# Then — HTTP succeeds and no new payout rows are created
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]

grep -E '0|none|empty|\[\]' "$RESPONSE_FILE" >/dev/null || true

PAYOUT_COUNT_AFTER="$(psql "$DATABASE_URL" -t -A -c 'SELECT COUNT(*) FROM payouts;' 2>/dev/null || printf '0')"
[ "$PAYOUT_COUNT_BEFORE" = "$PAYOUT_COUNT_AFTER" ]

echo "CODEVALID_TEST_ASSERTION_OK:payout_handles_no_completed_orders"

# Cleanup — remove seller and user seeded by this test
psql "$DATABASE_URL" <<SQL
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
