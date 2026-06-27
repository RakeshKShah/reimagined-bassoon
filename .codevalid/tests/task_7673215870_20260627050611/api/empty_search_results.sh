#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-empty-${CASE_SUFFIX}"
SELLER_ID="seller-empty-${CASE_SUFFIX}"
PRODUCT_ID="prod-100-${CASE_SUFFIX}"
RESPONSE_ONE_FILE="/tmp/empty_search_results_one_${CASE_SUFFIX}.json"
STATUS_ONE_FILE="/tmp/empty_search_results_one_${CASE_SUFFIX}.status"
RESPONSE_TWO_FILE="/tmp/empty_search_results_two_${CASE_SUFFIX}.json"
STATUS_TWO_FILE="/tmp/empty_search_results_two_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_ONE_FILE" "$STATUS_ONE_FILE" "$RESPONSE_TWO_FILE" "$STATUS_TWO_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id = '${PRODUCT_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','empty-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Empty Results Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES ('${PRODUCT_ID}','${SELLER_ID}','Standard Widget ${CASE_SUFFIX}','Normal widget','widgets',3300,7,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_ONE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?category=nonexistent" > "$STATUS_ONE_FILE"
curl -sS -o "$RESPONSE_TWO_FILE" -w '%{http_code}' \
  "$BASE_URL/products?keyword=zzznonexistent999" > "$STATUS_TWO_FILE"

# Then
[ "$(cat "$STATUS_ONE_FILE")" = "200" ]
[ "$(cat "$STATUS_TWO_FILE")" = "200" ]
jq -e 'type == "array" and length == 0' "$RESPONSE_ONE_FILE" >/dev/null
jq -e 'type == "array" and length == 0' "$RESPONSE_TWO_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:empty_search_results"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id = '${PRODUCT_ID}'; DELETE FROM products WHERE id = '${PRODUCT_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
