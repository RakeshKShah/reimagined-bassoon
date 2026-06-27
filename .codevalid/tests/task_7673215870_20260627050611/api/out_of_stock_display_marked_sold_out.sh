#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-oos-${CASE_SUFFIX}"
SELLER_ID="seller-oos-${CASE_SUFFIX}"
SOLD_OUT_ID="prod-010-${CASE_SUFFIX}"
IN_STOCK_ID="prod-011-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/out_of_stock_display_marked_sold_out_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/out_of_stock_display_marked_sold_out_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${SOLD_OUT_ID}','${IN_STOCK_ID}');
DELETE FROM products WHERE id IN ('${SOLD_OUT_ID}','${IN_STOCK_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','oos-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Accessories Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${SOLD_OUT_ID}','${SELLER_ID}','Vintage Watch ${CASE_SUFFIX}','Sold out watch','accessories',9900,0,TRUE,'ACTIVE'),
  ('${IN_STOCK_ID}','${SELLER_ID}','Modern Watch ${CASE_SUFFIX}','Available watch','accessories',12900,3,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg sold_out "$SOLD_OUT_ID" --arg in_stock "$IN_STOCK_ID" '
  type == "array" and
  (map(.id) | index($sold_out)) != null and
  (map(.id) | index($in_stock)) != null and
  ((map(select(.id == $sold_out))[0] | has("id") and has("title") and has("stockQty"))) and
  ((map(select(.id == $in_stock))[0] | has("id") and has("title") and has("stockQty"))) and
  ((map(select(.id == $sold_out))[0].stockQty) == 0) and
  ((map(select(.id == $in_stock))[0].stockQty) == 3)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:out_of_stock_display_marked_sold_out"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${SOLD_OUT_ID}','${IN_STOCK_ID}'); DELETE FROM products WHERE id IN ('${SOLD_OUT_ID}','${IN_STOCK_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
