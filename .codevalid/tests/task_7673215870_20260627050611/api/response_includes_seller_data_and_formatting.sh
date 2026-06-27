#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-format-${CASE_SUFFIX}"
SELLER_ID="seller-1-${CASE_SUFFIX}"
PRODUCT_Q_ID="prod-017-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/response_includes_seller_data_and_formatting_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/response_includes_seller_data_and_formatting_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id = '${PRODUCT_Q_ID}';
DELETE FROM products WHERE id = '${PRODUCT_Q_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','format-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','CozyGoods Inc.');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES ('${PRODUCT_Q_ID}','${SELLER_ID}','Quality Blanket ${CASE_SUFFIX}','Soft blanket for winter nights','HOME',5400,2,TRUE,'ACTIVE',NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?keyword=Blanket" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg id "$PRODUCT_Q_ID" --arg seller_id "$SELLER_ID" '
  type == "array" and
  (map(.id) | index($id)) != null and
  (map(select(.id == $id))[0].seller.id == $seller_id) and
  ((map(select(.id == $id))[0].seller.storeName == "CozyGoods Inc.") or (map(select(.id == $id))[0].seller.companyName == "CozyGoods Inc.")) and
  (map(select(.id == $id))[0].stockQty == 2)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:response_includes_seller_data_and_formatting"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id = '${PRODUCT_Q_ID}'; DELETE FROM products WHERE id = '${PRODUCT_Q_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
