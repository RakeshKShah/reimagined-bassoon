#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-removed-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-removed-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="seller-user-removed-${CASE_SUFFIX}"
SELLER_ID="seller-removed-${CASE_SUFFIX}"
ACTIVE_ID="prod-080-${CASE_SUFFIX}"
REMOVED_ID="prod-081-${CASE_SUFFIX}"
REGULAR_RESPONSE_FILE="/tmp/removed_products_regular_${CASE_SUFFIX}.json"
REGULAR_STATUS_FILE="/tmp/removed_products_regular_${CASE_SUFFIX}.status"
ADMIN_RESPONSE_FILE="/tmp/removed_products_admin_${CASE_SUFFIX}.json"
ADMIN_STATUS_FILE="/tmp/removed_products_admin_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$REGULAR_RESPONSE_FILE" "$REGULAR_STATUS_FILE" "$ADMIN_RESPONSE_FILE" "$ADMIN_STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${ACTIVE_ID}','${REMOVED_ID}');
DELETE FROM products WHERE id IN ('${ACTIVE_ID}','${REMOVED_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}');
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${ADMIN_ID}','${ADMIN_EMAIL}','seed-hash','ADMIN','ACTIVE'),
  ('${SELLER_USER_ID}','removed-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Removed Filter Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${ACTIVE_ID}','${SELLER_ID}','Active Product ${CASE_SUFFIX}','Active listing','general',5100,4,TRUE,'ACTIVE'),
  ('${REMOVED_ID}','${SELLER_ID}','Removed Product ${CASE_SUFFIX}','Removed listing','general',5200,4,TRUE,'REMOVED');
SQL
ADMIN_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'ADMIN', status: 'ACTIVE'}, process.argv[3]));" "$ADMIN_ID" "$ADMIN_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$REGULAR_RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$REGULAR_STATUS_FILE"
curl -sS -o "$ADMIN_RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "$BASE_URL/products" > "$ADMIN_STATUS_FILE"

# Then
[ "$(cat "$REGULAR_STATUS_FILE")" = "200" ]
[ "$(cat "$ADMIN_STATUS_FILE")" = "200" ]
jq -e --arg active "$ACTIVE_ID" --arg removed "$REMOVED_ID" '
  type == "array" and
  (map(.id) | index($active)) != null and
  (map(.id) | index($removed)) == null
' "$REGULAR_RESPONSE_FILE" >/dev/null
jq -e --arg active "$ACTIVE_ID" --arg removed "$REMOVED_ID" '
  type == "array" and
  (map(.id) | index($active)) != null and
  (map(.id) | index($removed)) == null
' "$ADMIN_RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:removed_products_excluded_from_all_users"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${ACTIVE_ID}','${REMOVED_ID}'); DELETE FROM products WHERE id IN ('${ACTIVE_ID}','${REMOVED_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}');" >/dev/null
