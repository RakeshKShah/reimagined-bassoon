#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-instock-${CASE_SUFFIX}"
SELLER_ID="seller-instock-${CASE_SUFFIX}"
AVAILABLE_ID="prod-050-${CASE_SUFFIX}"
UNAVAILABLE_ID="prod-051-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/filter_in_stock_products_only_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/filter_in_stock_products_only_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${AVAILABLE_ID}','${UNAVAILABLE_ID}');
DELETE FROM products WHERE id IN ('${AVAILABLE_ID}','${UNAVAILABLE_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','instock-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','In Stock Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${AVAILABLE_ID}','${SELLER_ID}','Available Item ${CASE_SUFFIX}','Available inventory','general',2100,5,TRUE,'ACTIVE'),
  ('${UNAVAILABLE_ID}','${SELLER_ID}','Unavailable Item ${CASE_SUFFIX}','Out of stock inventory','general',2200,0,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?in_stock=true" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg available "$AVAILABLE_ID" --arg unavailable "$UNAVAILABLE_ID" '
  type == "array" and
  (map(.id) | index($available)) != null and
  (map(.id) | index($unavailable)) == null and
  all(.[]; .stockQty > 0)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:filter_in_stock_products_only"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${AVAILABLE_ID}','${UNAVAILABLE_ID}'); DELETE FROM products WHERE id IN ('${AVAILABLE_ID}','${UNAVAILABLE_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
