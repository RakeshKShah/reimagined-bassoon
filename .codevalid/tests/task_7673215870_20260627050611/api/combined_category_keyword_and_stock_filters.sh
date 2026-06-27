#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-combined-${CASE_SUFFIX}"
SELLER_ID="seller-combined-${CASE_SUFFIX}"
PRODUCT_K_ID="prod-011-${CASE_SUFFIX}"
PRODUCT_L_ID="prod-012-${CASE_SUFFIX}"
PRODUCT_M_ID="prod-013-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/combined_category_keyword_and_stock_filters_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/combined_category_keyword_and_stock_filters_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${PRODUCT_K_ID}','${PRODUCT_L_ID}','${PRODUCT_M_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT_K_ID}','${PRODUCT_L_ID}','${PRODUCT_M_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','combined-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Combined Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES
  ('${PRODUCT_K_ID}','${SELLER_ID}','Kitchen Knife ${CASE_SUFFIX}','Professional chef knife.','KITCHEN',4500,3,TRUE,'ACTIVE',NOW() - INTERVAL '3 minutes'),
  ('${PRODUCT_L_ID}','${SELLER_ID}','Knife Sharpener ${CASE_SUFFIX}','Keep your blades sharp and every knife precise.','KITCHEN',1800,2,TRUE,'ACTIVE',NOW() - INTERVAL '2 minutes'),
  ('${PRODUCT_M_ID}','${SELLER_ID}','Knife Set ${CASE_SUFFIX}','Complete set.','KITCHEN',6500,0,TRUE,'ACTIVE',NOW() - INTERVAL '1 minute');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?category=KITCHEN&keyword=knife&in_stock=true" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg k "$PRODUCT_K_ID" --arg l "$PRODUCT_L_ID" --arg m "$PRODUCT_M_ID" '
  type == "array" and
  (map(.id) | index($k)) != null and
  (map(.id) | index($l)) != null and
  (map(.id) | index($m)) == null and
  all(.[]; .category == "KITCHEN" and .stockQty > 0)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:combined_category_keyword_and_stock_filters"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${PRODUCT_K_ID}','${PRODUCT_L_ID}','${PRODUCT_M_ID}'); DELETE FROM products WHERE id IN ('${PRODUCT_K_ID}','${PRODUCT_L_ID}','${PRODUCT_M_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
