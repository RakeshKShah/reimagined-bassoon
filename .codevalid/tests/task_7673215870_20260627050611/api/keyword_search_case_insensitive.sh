#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-case-${CASE_SUFFIX}"
SELLER_ID="seller-case-${CASE_SUFFIX}"
PRODUCT_ID="prod-130-${CASE_SUFFIX}"
RESP_UPPER="/tmp/keyword_search_case_insensitive_upper_${CASE_SUFFIX}.json"
STAT_UPPER="/tmp/keyword_search_case_insensitive_upper_${CASE_SUFFIX}.status"
RESP_LOWER="/tmp/keyword_search_case_insensitive_lower_${CASE_SUFFIX}.json"
STAT_LOWER="/tmp/keyword_search_case_insensitive_lower_${CASE_SUFFIX}.status"
RESP_MIXED="/tmp/keyword_search_case_insensitive_mixed_${CASE_SUFFIX}.json"
STAT_MIXED="/tmp/keyword_search_case_insensitive_mixed_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESP_UPPER" "$STAT_UPPER" "$RESP_LOWER" "$STAT_LOWER" "$RESP_MIXED" "$STAT_MIXED"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id = '${PRODUCT_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','case-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Case Search Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES ('${PRODUCT_ID}','${SELLER_ID}','SMARTPHONE Device ${CASE_SUFFIX}','Modern smartphone','electronics',73000,4,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESP_UPPER" -w '%{http_code}' "$BASE_URL/products?keyword=SMARTPHONE" > "$STAT_UPPER"
curl -sS -o "$RESP_LOWER" -w '%{http_code}' "$BASE_URL/products?keyword=smartphone" > "$STAT_LOWER"
curl -sS -o "$RESP_MIXED" -w '%{http_code}' "$BASE_URL/products?keyword=SmArTpHoNe" > "$STAT_MIXED"

# Then
[ "$(cat "$STAT_UPPER")" = "200" ]
[ "$(cat "$STAT_LOWER")" = "200" ]
[ "$(cat "$STAT_MIXED")" = "200" ]
jq -e --arg product "$PRODUCT_ID" '(map(.id) | index($product)) != null' "$RESP_UPPER" >/dev/null
jq -e --arg product "$PRODUCT_ID" '(map(.id) | index($product)) != null' "$RESP_LOWER" >/dev/null
jq -e --arg product "$PRODUCT_ID" '(map(.id) | index($product)) != null' "$RESP_MIXED" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:keyword_search_case_insensitive"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id = '${PRODUCT_ID}'; DELETE FROM products WHERE id = '${PRODUCT_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
