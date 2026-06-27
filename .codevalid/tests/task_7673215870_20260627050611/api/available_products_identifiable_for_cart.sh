#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-cart-${CASE_SUFFIX}"
SELLER_ID="seller-cart-${CASE_SUFFIX}"
AVAILABLE_ID="prod-120-${CASE_SUFFIX}"
OUT_OF_STOCK_ID="prod-121-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/available_products_identifiable_for_cart_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/available_products_identifiable_for_cart_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${AVAILABLE_ID}','${OUT_OF_STOCK_ID}');
DELETE FROM products WHERE id IN ('${AVAILABLE_ID}','${OUT_OF_STOCK_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','cart-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Cart Visibility Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${AVAILABLE_ID}','${SELLER_ID}','Add to Cart Item ${CASE_SUFFIX}','Cart-ready item','general',6100,10,TRUE,'ACTIVE'),
  ('${OUT_OF_STOCK_ID}','${SELLER_ID}','Out of Stock Item ${CASE_SUFFIX}','Unavailable item','general',6200,0,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg available "$AVAILABLE_ID" --arg unavailable "$OUT_OF_STOCK_ID" '
  type == "array" and
  ((map(select(.id == $available))[0].stockQty) == 10) and
  ((map(select(.id == $unavailable))[0].stockQty) == 0)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:available_products_identifiable_for_cart"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${AVAILABLE_ID}','${OUT_OF_STOCK_ID}'); DELETE FROM products WHERE id IN ('${AVAILABLE_ID}','${OUT_OF_STOCK_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
