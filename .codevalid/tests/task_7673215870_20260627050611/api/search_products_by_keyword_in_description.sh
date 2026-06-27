#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-keyword-desc-${CASE_SUFFIX}"
SELLER_ID="seller-keyword-desc-${CASE_SUFFIX}"
MATCH_ID="prod-040-${CASE_SUFFIX}"
NONMATCH_ID="prod-041-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/search_products_by_keyword_in_description_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/search_products_by_keyword_in_description_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${MATCH_ID}','${NONMATCH_ID}');
DELETE FROM products WHERE id IN ('${MATCH_ID}','${NONMATCH_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','keyword-desc-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Keyword Description Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${MATCH_ID}','${SELLER_ID}','Premium Speaker ${CASE_SUFFIX}','Portable wireless audio with deep bass','audio',15900,6,TRUE,'ACTIVE'),
  ('${NONMATCH_ID}','${SELLER_ID}','Desktop Stand ${CASE_SUFFIX}','Adjustable stand for monitors','accessories',4900,9,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?keyword=bass" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg match "$MATCH_ID" --arg nonmatch "$NONMATCH_ID" '
  type == "array" and
  (map(.id) | index($match)) != null and
  (map(.id) | index($nonmatch)) == null
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:search_products_by_keyword_in_description"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${MATCH_ID}','${NONMATCH_ID}'); DELETE FROM products WHERE id IN ('${MATCH_ID}','${NONMATCH_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
