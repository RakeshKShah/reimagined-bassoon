#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-approve-${CASE_SUFFIX}"
SELLER_ID="seller-approve-${CASE_SUFFIX}"
EMAIL="approve-${CASE_SUFFIX}@example.com"
PRODUCT_ID_1="prod-approve-1-${CASE_SUFFIX}"
PRODUCT_ID_2="prod-approve-2-${CASE_SUFFIX}"
PRODUCT_ID_3="prod-approve-3-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/approve_new_seller_success_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/approve_new_seller_success_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PRODUCT_ID_1}', '${PRODUCT_ID_2}', '${PRODUCT_ID_3}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create a pending seller with hidden products awaiting approval
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('${USER_ID}', '${EMAIL}', 'seed-hash', 'SELLER', 'PENDING', NOW());"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Approve Store ${CASE_SUFFIX}', 'Pending seller approval');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at) VALUES ('${PRODUCT_ID_1}', '${SELLER_ID}', 'Approve Product 1 ${CASE_SUFFIX}', 'Seed product 1', 'Admin', 1100, 5, false, 'ACTIVE', NOW()), ('${PRODUCT_ID_2}', '${SELLER_ID}', 'Approve Product 2 ${CASE_SUFFIX}', 'Seed product 2', 'Admin', 1200, 6, false, 'ACTIVE', NOW()), ('${PRODUCT_ID_3}', '${SELLER_ID}', 'Approve Product 3 ${CASE_SUFFIX}', 'Seed product 3', 'Admin', 1300, 7, false, 'ACTIVE', NOW());"

# When — approve the seller
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  --data '{"status":"ACTIVE"}' > "$STATUS_FILE"

# Then — verify response and activation side effects
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"${SELLER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
USER_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id = '${USER_ID}';")"
[ "$USER_STATUS" = "ACTIVE" ]
VISIBLE_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id = '${SELLER_ID}' AND visible = true;")"
[ "$VISIBLE_COUNT" = "3" ]
HIDDEN_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id = '${SELLER_ID}' AND visible = false;")"
[ "$HIDDEN_COUNT" = "0" ]

echo "CODEVALID_TEST_ASSERTION_OK:approve_new_seller_success"

# Cleanup — handled by trap to remove seeded products, seller profile, and user
