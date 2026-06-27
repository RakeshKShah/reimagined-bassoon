#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_USER_ID="admin-1-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-admin-view-${CASE_SUFFIX}"
SELLER_ID="seller-admin-view-${CASE_SUFFIX}"
PRODUCT_N_ID="prod-014-${CASE_SUFFIX}"
PUBLIC_RESPONSE_FILE="/tmp/admin_sees_non_visible_products_public_${CASE_SUFFIX}.json"
PUBLIC_STATUS_FILE="/tmp/admin_sees_non_visible_products_public_${CASE_SUFFIX}.status"
ADMIN_RESPONSE_FILE="/tmp/admin_sees_non_visible_products_admin_${CASE_SUFFIX}.json"
ADMIN_STATUS_FILE="/tmp/admin_sees_non_visible_products_admin_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$PUBLIC_RESPONSE_FILE" "$PUBLIC_STATUS_FILE" "$ADMIN_RESPONSE_FILE" "$ADMIN_STATUS_FILE"; }
trap cleanup_files EXIT
ADMIN_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1]}, process.argv[2]));" "$ADMIN_USER_ID" "$JWT_SECRET")"

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id = '${PRODUCT_N_ID}';
DELETE FROM products WHERE id = '${PRODUCT_N_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${ADMIN_USER_ID}','${SELLER_USER_ID}');
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${ADMIN_USER_ID}','admin-${CASE_SUFFIX}@example.com','seed-hash','ADMIN','ACTIVE'),
  ('${SELLER_USER_ID}','seller-admin-view-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Admin Visibility Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES ('${PRODUCT_N_ID}','${SELLER_ID}','Nano Drone ${CASE_SUFFIX}','Hidden from public catalog','DRONES',49900,5,FALSE,'ACTIVE',NOW());
SQL

# When
curl -sS -o "$PUBLIC_RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$PUBLIC_STATUS_FILE"
curl -sS -o "$ADMIN_RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "$BASE_URL/products" > "$ADMIN_STATUS_FILE"

# Then
[ "$(cat "$PUBLIC_STATUS_FILE")" = "200" ]
[ "$(cat "$ADMIN_STATUS_FILE")" = "200" ]
jq -e --arg hidden "$PRODUCT_N_ID" 'type == "array" and (map(.id) | index($hidden)) == null' "$PUBLIC_RESPONSE_FILE" >/dev/null
jq -e --arg hidden "$PRODUCT_N_ID" 'type == "array" and (map(.id) | index($hidden)) != null' "$ADMIN_RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_sees_non_visible_products"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id = '${PRODUCT_N_ID}'; DELETE FROM products WHERE id = '${PRODUCT_N_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id IN ('${ADMIN_USER_ID}','${SELLER_USER_ID}');" >/dev/null
