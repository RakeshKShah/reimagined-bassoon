#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-suspend-${CASE_SUFFIX}"
SELLER_ID="seller-suspend-${CASE_SUFFIX}"
EMAIL="suspend-${CASE_SUFFIX}@example.com"
PRODUCT_ID_1="prod-suspend-1-${CASE_SUFFIX}"
PRODUCT_ID_2="prod-suspend-2-${CASE_SUFFIX}"
PRODUCT_ID_3="prod-suspend-3-${CASE_SUFFIX}"
PRODUCT_ID_4="prod-suspend-4-${CASE_SUFFIX}"
PRODUCT_ID_5="prod-suspend-5-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/suspend_seller_hides_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/suspend_seller_hides_products_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PRODUCT_ID_1}', '${PRODUCT_ID_2}', '${PRODUCT_ID_3}', '${PRODUCT_ID_4}', '${PRODUCT_ID_5}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create an active seller with visible products
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('${USER_ID}', '${EMAIL}', 'seed-hash', 'SELLER', 'ACTIVE', NOW());"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Suspend Store ${CASE_SUFFIX}', 'Active seller before suspension');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at) VALUES ('${PRODUCT_ID_1}', '${SELLER_ID}', 'Suspend Product 1 ${CASE_SUFFIX}', 'Seed product 1', 'Admin', 2100, 5, true, 'ACTIVE', NOW()), ('${PRODUCT_ID_2}', '${SELLER_ID}', 'Suspend Product 2 ${CASE_SUFFIX}', 'Seed product 2', 'Admin', 2200, 6, true, 'ACTIVE', NOW()), ('${PRODUCT_ID_3}', '${SELLER_ID}', 'Suspend Product 3 ${CASE_SUFFIX}', 'Seed product 3', 'Admin', 2300, 7, true, 'ACTIVE', NOW()), ('${PRODUCT_ID_4}', '${SELLER_ID}', 'Suspend Product 4 ${CASE_SUFFIX}', 'Seed product 4', 'Admin', 2400, 8, true, 'ACTIVE', NOW()), ('${PRODUCT_ID_5}', '${SELLER_ID}', 'Suspend Product 5 ${CASE_SUFFIX}', 'Seed product 5', 'Admin', 2500, 9, true, 'ACTIVE', NOW());"

# When — suspend the seller
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  --data '{"status":"SUSPENDED"}' > "$STATUS_FILE"

# Then — verify response and hidden-product side effects
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"${SELLER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SUSPENDED"' "$RESPONSE_FILE" >/dev/null
USER_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id = '${USER_ID}';")"
[ "$USER_STATUS" = "SUSPENDED" ]
VISIBLE_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id = '${SELLER_ID}' AND visible = true;")"
[ "$VISIBLE_COUNT" = "0" ]
HIDDEN_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id = '${SELLER_ID}' AND visible = false;")"
[ "$HIDDEN_COUNT" = "5" ]

echo "CODEVALID_TEST_ASSERTION_OK:suspend_seller_hides_products"

# Cleanup — handled by trap to remove seeded products, seller profile, and user
