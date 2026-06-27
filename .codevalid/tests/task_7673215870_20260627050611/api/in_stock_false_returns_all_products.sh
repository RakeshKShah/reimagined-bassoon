#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-stockflag-${CASE_SUFFIX}"
SELLER_ID="seller-stockflag-${CASE_SUFFIX}"
STOCKED_ID="prod-140-${CASE_SUFFIX}"
UNSTOCKED_ID="prod-141-${CASE_SUFFIX}"
RESP_NONE="/tmp/in_stock_false_returns_all_products_none_${CASE_SUFFIX}.json"
STAT_NONE="/tmp/in_stock_false_returns_all_products_none_${CASE_SUFFIX}.status"
RESP_FALSE="/tmp/in_stock_false_returns_all_products_false_${CASE_SUFFIX}.json"
STAT_FALSE="/tmp/in_stock_false_returns_all_products_false_${CASE_SUFFIX}.status"
RESP_INVALID="/tmp/in_stock_false_returns_all_products_invalid_${CASE_SUFFIX}.json"
STAT_INVALID="/tmp/in_stock_false_returns_all_products_invalid_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESP_NONE" "$STAT_NONE" "$RESP_FALSE" "$STAT_FALSE" "$RESP_INVALID" "$STAT_INVALID"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${STOCKED_ID}','${UNSTOCKED_ID}');
DELETE FROM products WHERE id IN ('${STOCKED_ID}','${UNSTOCKED_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','stockflag-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Stock Flag Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${STOCKED_ID}','${SELLER_ID}','Stocked Item ${CASE_SUFFIX}','In stock item','general',4100,5,TRUE,'ACTIVE'),
  ('${UNSTOCKED_ID}','${SELLER_ID}','Unstocked Item ${CASE_SUFFIX}','Out of stock item','general',4200,0,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESP_NONE" -w '%{http_code}' "$BASE_URL/products" > "$STAT_NONE"
curl -sS -o "$RESP_FALSE" -w '%{http_code}' "$BASE_URL/products?in_stock=false" > "$STAT_FALSE"
curl -sS -o "$RESP_INVALID" -w '%{http_code}' "$BASE_URL/products?in_stock=invalid" > "$STAT_INVALID"

# Then
[ "$(cat "$STAT_NONE")" = "200" ]
[ "$(cat "$STAT_FALSE")" = "200" ]
[ "$(cat "$STAT_INVALID")" = "200" ]
jq -e --arg stocked "$STOCKED_ID" --arg unstocked "$UNSTOCKED_ID" '
  (map(.id) | index($stocked)) != null and
  (map(.id) | index($unstocked)) != null
' "$RESP_NONE" >/dev/null
jq -e --arg stocked "$STOCKED_ID" --arg unstocked "$UNSTOCKED_ID" '
  (map(.id) | index($stocked)) != null and
  (map(.id) | index($unstocked)) != null
' "$RESP_FALSE" >/dev/null
jq -e --arg stocked "$STOCKED_ID" --arg unstocked "$UNSTOCKED_ID" '
  (map(.id) | index($stocked)) != null and
  (map(.id) | index($unstocked)) != null
' "$RESP_INVALID" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:in_stock_false_returns_all_products"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${STOCKED_ID}','${UNSTOCKED_ID}'); DELETE FROM products WHERE id IN ('${STOCKED_ID}','${UNSTOCKED_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
