#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-keyword-title-${CASE_SUFFIX}"
SELLER_ID="seller-keyword-title-${CASE_SUFFIX}"
WIRELESS_ID="prod-030-${CASE_SUFFIX}"
USB_ID="prod-031-${CASE_SUFFIX}"
RESPONSE_ONE_FILE="/tmp/search_products_by_keyword_in_title_one_${CASE_SUFFIX}.json"
STATUS_ONE_FILE="/tmp/search_products_by_keyword_in_title_one_${CASE_SUFFIX}.status"
RESPONSE_TWO_FILE="/tmp/search_products_by_keyword_in_title_two_${CASE_SUFFIX}.json"
STATUS_TWO_FILE="/tmp/search_products_by_keyword_in_title_two_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_ONE_FILE" "$STATUS_ONE_FILE" "$RESPONSE_TWO_FILE" "$STATUS_TWO_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${WIRELESS_ID}','${USB_ID}');
DELETE FROM products WHERE id IN ('${WIRELESS_ID}','${USB_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','keyword-title-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Keyword Title Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${WIRELESS_ID}','${SELLER_ID}','Wireless Bluetooth Headphones ${CASE_SUFFIX}','High quality audio','electronics',12900,8,TRUE,'ACTIVE'),
  ('${USB_ID}','${SELLER_ID}','USB Charging Cable ${CASE_SUFFIX}','Fast charging cable','electronics',1900,15,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_ONE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?keyword=wireless" > "$STATUS_ONE_FILE"
curl -sS -o "$RESPONSE_TWO_FILE" -w '%{http_code}' \
  "$BASE_URL/products?keyword=USB" > "$STATUS_TWO_FILE"

# Then
[ "$(cat "$STATUS_ONE_FILE")" = "200" ]
[ "$(cat "$STATUS_TWO_FILE")" = "200" ]
jq -e --arg wireless "$WIRELESS_ID" --arg usb "$USB_ID" '
  type == "array" and
  length == 1 and
  .[0].id == $wireless and
  (map(.id) | index($usb)) == null
' "$RESPONSE_ONE_FILE" >/dev/null
jq -e --arg usb "$USB_ID" '
  type == "array" and
  (map(.id) | index($usb)) != null
' "$RESPONSE_TWO_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:search_products_by_keyword_in_title"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${WIRELESS_ID}','${USB_ID}'); DELETE FROM products WHERE id IN ('${WIRELESS_ID}','${USB_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
