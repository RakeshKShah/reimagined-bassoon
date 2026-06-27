#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-browse-${CASE_SUFFIX}"
SELLER_ID="seller-browse-${CASE_SUFFIX}"
VISIBLE_IN_STOCK_ID="prod-001-${CASE_SUFFIX}"
VISIBLE_OUT_OF_STOCK_ID="prod-002-${CASE_SUFFIX}"
HIDDEN_ID="prod-003-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/browse_all_products_success_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/browse_all_products_success_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${VISIBLE_IN_STOCK_ID}','${VISIBLE_OUT_OF_STOCK_ID}','${HIDDEN_ID}');
DELETE FROM products WHERE id IN ('${VISIBLE_IN_STOCK_ID}','${VISIBLE_OUT_OF_STOCK_ID}','${HIDDEN_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','browse-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Browse Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES
  ('${VISIBLE_IN_STOCK_ID}','${SELLER_ID}','Widget A ${CASE_SUFFIX}','Visible in stock product','electronics',1500,10,TRUE,'ACTIVE',NOW() - INTERVAL '3 minutes'),
  ('${VISIBLE_OUT_OF_STOCK_ID}','${SELLER_ID}','Widget B ${CASE_SUFFIX}','Visible out of stock product','electronics',1700,0,TRUE,'ACTIVE',NOW() - INTERVAL '2 minutes'),
  ('${HIDDEN_ID}','${SELLER_ID}','Widget C ${CASE_SUFFIX}','Hidden product','electronics',1900,5,FALSE,'ACTIVE',NOW() - INTERVAL '1 minutes');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg in_stock "$VISIBLE_IN_STOCK_ID" --arg sold_out "$VISIBLE_OUT_OF_STOCK_ID" --arg hidden "$HIDDEN_ID" '
  type == "array" and
  (map(.id) | index($in_stock)) != null and
  (map(.id) | index($sold_out)) != null and
  (map(.id) | index($hidden)) == null and
  ((map(select(.id == $sold_out))[0].stockQty) == 0) and
  ((map(select(.id == $in_stock))[0].stockQty) == 10) and
  ((map(select(.id == $sold_out))[0].createdAt) > (map(select(.id == $in_stock))[0].createdAt))
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:browse_all_products_success"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${VISIBLE_IN_STOCK_ID}','${VISIBLE_OUT_OF_STOCK_ID}','${HIDDEN_ID}'); DELETE FROM products WHERE id IN ('${VISIBLE_IN_STOCK_ID}','${VISIBLE_OUT_OF_STOCK_ID}','${HIDDEN_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
