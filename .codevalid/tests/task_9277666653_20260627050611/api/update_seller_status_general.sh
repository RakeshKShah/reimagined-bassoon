#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-inactive-${CASE_SUFFIX}"
SELLER_ID="seller-inactive-${CASE_SUFFIX}"
EMAIL="inactive-${CASE_SUFFIX}@example.com"
PRODUCT_ID_1="prod-inactive-1-${CASE_SUFFIX}"
PRODUCT_ID_2="prod-inactive-2-${CASE_SUFFIX}"
PRODUCT_ID_3="prod-inactive-3-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/update_seller_status_general_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/update_seller_status_general_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PRODUCT_ID_1}', '${PRODUCT_ID_2}', '${PRODUCT_ID_3}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create an active seller whose product visibility should remain unchanged
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('${USER_ID}', '${EMAIL}', 'seed-hash', 'SELLER', 'ACTIVE', NOW());"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Inactive Store ${CASE_SUFFIX}', 'Seller for general status update');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at) VALUES ('${PRODUCT_ID_1}', '${SELLER_ID}', 'General Product 1 ${CASE_SUFFIX}', 'Seed product 1', 'Admin', 3100, 3, true, 'ACTIVE', NOW()), ('${PRODUCT_ID_2}', '${SELLER_ID}', 'General Product 2 ${CASE_SUFFIX}', 'Seed product 2', 'Admin', 3200, 4, false, 'ACTIVE', NOW()), ('${PRODUCT_ID_3}', '${SELLER_ID}', 'General Product 3 ${CASE_SUFFIX}', 'Seed product 3', 'Admin', 3300, 5, true, 'ACTIVE', NOW());"
BEFORE_TRUE="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id = '${SELLER_ID}' AND visible = true;")"
BEFORE_FALSE="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id = '${SELLER_ID}' AND visible = false;")"

# When — update seller to another valid non-active/non-suspended state
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  --data '{"status":"INACTIVE"}' > "$STATUS_FILE"

# Then — verify status change without product visibility changes
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"${SELLER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"INACTIVE"' "$RESPONSE_FILE" >/dev/null
USER_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id = '${USER_ID}';")"
[ "$USER_STATUS" = "INACTIVE" ]
AFTER_TRUE="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id = '${SELLER_ID}' AND visible = true;")"
AFTER_FALSE="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id = '${SELLER_ID}' AND visible = false;")"
[ "$AFTER_TRUE" = "$BEFORE_TRUE" ]
[ "$AFTER_FALSE" = "$BEFORE_FALSE" ]

echo "CODEVALID_TEST_ASSERTION_OK:update_seller_status_general"

# Cleanup — handled by trap to remove seeded products, seller profile, and user
