#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-category-${CASE_SUFFIX}"
SELLER_ID="seller-category-${CASE_SUFFIX}"
COMPUTER_ID="prod-020-${CASE_SUFFIX}"
PHONE_ID="prod-021-${CASE_SUFFIX}"
TABLET_ID="prod-022-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/search_products_by_category_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/search_products_by_category_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${COMPUTER_ID}','${PHONE_ID}','${TABLET_ID}');
DELETE FROM products WHERE id IN ('${COMPUTER_ID}','${PHONE_ID}','${TABLET_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','category-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Category Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${COMPUTER_ID}','${SELLER_ID}','Laptop A ${CASE_SUFFIX}','Computer product','computers',99900,4,TRUE,'ACTIVE'),
  ('${PHONE_ID}','${SELLER_ID}','Phone B ${CASE_SUFFIX}','Phone product','phones',79900,7,TRUE,'ACTIVE'),
  ('${TABLET_ID}','${SELLER_ID}','Tablet C ${CASE_SUFFIX}','Tablet product','tablets',59900,3,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?category=phones" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg phone "$PHONE_ID" --arg computer "$COMPUTER_ID" --arg tablet "$TABLET_ID" '
  type == "array" and
  length == 1 and
  .[0].id == $phone and
  .[0].category == "phones" and
  (map(.id) | index($computer)) == null and
  (map(.id) | index($tablet)) == null
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:search_products_by_category"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${COMPUTER_ID}','${PHONE_ID}','${TABLET_ID}'); DELETE FROM products WHERE id IN ('${COMPUTER_ID}','${PHONE_ID}','${TABLET_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
