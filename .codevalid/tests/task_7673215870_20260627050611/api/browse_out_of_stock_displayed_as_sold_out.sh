#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-soldout-${CASE_SUFFIX}"
SELLER_ID="seller-soldout-${CASE_SUFFIX}"
PRODUCT_C_ID="prod-003-${CASE_SUFFIX}"
PRODUCT_D_ID="prod-004-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/browse_out_of_stock_displayed_as_sold_out_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/browse_out_of_stock_displayed_as_sold_out_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${PRODUCT_C_ID}','${PRODUCT_D_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT_C_ID}','${PRODUCT_D_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','soldout-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Sold Out Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES
  ('${PRODUCT_C_ID}','${SELLER_ID}','Gamma Device ${CASE_SUFFIX}','Should surface as sold out','ELECTRONICS',2200,0,TRUE,'ACTIVE',NOW() - INTERVAL '2 minutes'),
  ('${PRODUCT_D_ID}','${SELLER_ID}','Delta Tool ${CASE_SUFFIX}','Available comparison product','TOOLS',1300,3,TRUE,'ACTIVE',NOW() - INTERVAL '1 minute');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg sold_out "$PRODUCT_C_ID" --arg available "$PRODUCT_D_ID" '
  type == "array" and
  (map(.id) | index($sold_out)) != null and
  (map(.id) | index($available)) != null and
  (map(select(.id == $sold_out))[0].stockQty == 0) and
  (map(select(.id == $available))[0].stockQty == 3)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:browse_out_of_stock_displayed_as_sold_out"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${PRODUCT_C_ID}','${PRODUCT_D_ID}'); DELETE FROM products WHERE id IN ('${PRODUCT_C_ID}','${PRODUCT_D_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
