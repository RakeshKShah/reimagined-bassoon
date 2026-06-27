#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-user-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="seller-user-admin-view-${CASE_SUFFIX}"
SELLER_ID="seller-admin-view-${CASE_SUFFIX}"
HIDDEN_ID="prod-060-${CASE_SUFFIX}"
PUBLIC_ID="prod-061-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/admin_can_view_non_visible_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_can_view_non_visible_products_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${HIDDEN_ID}','${PUBLIC_ID}');
DELETE FROM products WHERE id IN ('${HIDDEN_ID}','${PUBLIC_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}');
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${ADMIN_ID}','${ADMIN_EMAIL}','seed-hash','ADMIN','ACTIVE'),
  ('${SELLER_USER_ID}','admin-view-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Admin View Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${HIDDEN_ID}','${SELLER_ID}','Draft Product ${CASE_SUFFIX}','Hidden product','general',4500,2,FALSE,'ACTIVE'),
  ('${PUBLIC_ID}','${SELLER_ID}','Public Product ${CASE_SUFFIX}','Visible product','general',4700,3,TRUE,'ACTIVE');
SQL
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'ADMIN', status: 'ACTIVE'}, process.argv[3]));" "$ADMIN_ID" "$ADMIN_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg hidden "$HIDDEN_ID" --arg public "$PUBLIC_ID" '
  type == "array" and
  (map(.id) | index($hidden)) != null and
  (map(.id) | index($public)) != null
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_can_view_non_visible_products"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${HIDDEN_ID}','${PUBLIC_ID}'); DELETE FROM products WHERE id IN ('${HIDDEN_ID}','${PUBLIC_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}');" >/dev/null
