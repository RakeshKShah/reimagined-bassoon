#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-combined-${CASE_SUFFIX}"
SELLER_ID="seller-combined-${CASE_SUFFIX}"
MATCH_ID="prod-090-${CASE_SUFFIX}"
KEYWORD_MISS_ID="prod-091-${CASE_SUFFIX}"
CATEGORY_MISS_ID="prod-092-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/combined_search_and_filter_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/combined_search_and_filter_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${MATCH_ID}','${KEYWORD_MISS_ID}','${CATEGORY_MISS_ID}');
DELETE FROM products WHERE id IN ('${MATCH_ID}','${KEYWORD_MISS_ID}','${CATEGORY_MISS_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','combined-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Combined Filter Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${MATCH_ID}','${SELLER_ID}','Running Shoes ${CASE_SUFFIX}','Athletic footwear','shoes',8900,8,TRUE,'ACTIVE'),
  ('${KEYWORD_MISS_ID}','${SELLER_ID}','Walking Shoes ${CASE_SUFFIX}','Comfortable casual shoes','shoes',8400,8,TRUE,'ACTIVE'),
  ('${CATEGORY_MISS_ID}','${SELLER_ID}','Running Watch ${CASE_SUFFIX}','GPS running tracker','electronics',13900,5,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?category=shoes&keyword=running" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg match "$MATCH_ID" --arg keyword_miss "$KEYWORD_MISS_ID" --arg category_miss "$CATEGORY_MISS_ID" '
  type == "array" and
  length == 1 and
  .[0].id == $match and
  (map(.id) | index($keyword_miss)) == null and
  (map(.id) | index($category_miss)) == null
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:combined_search_and_filter"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${MATCH_ID}','${KEYWORD_MISS_ID}','${CATEGORY_MISS_ID}'); DELETE FROM products WHERE id IN ('${MATCH_ID}','${KEYWORD_MISS_ID}','${CATEGORY_MISS_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
