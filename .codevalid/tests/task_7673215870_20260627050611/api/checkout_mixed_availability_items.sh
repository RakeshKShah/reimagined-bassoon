#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="user-buyer-11-${CASE_SUFFIX}"
BUYER_EMAIL="checkout-mixed-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="seller-user-11-${CASE_SUFFIX}"
SELLER_EMAIL="checkout-mixed-seller-${CASE_SUFFIX}@example.com"
SELLER_ID="seller-11-${CASE_SUFFIX}"
PRODUCT_OK_ID="prod-available-a-${CASE_SUFFIX}"
PRODUCT_BAD_ID="prod-soldout-b-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/checkout_mixed_availability_items_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_mixed_availability_items_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${PRODUCT_OK_ID}','${PRODUCT_BAD_ID}');
DELETE FROM orders WHERE buyer_id = '${BUYER_ID}';
DELETE FROM products WHERE id IN ('${PRODUCT_OK_ID}','${PRODUCT_BAD_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${BUYER_ID}','${SELLER_USER_ID}') OR email IN ('${BUYER_EMAIL}','${SELLER_EMAIL}');
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${BUYER_ID}','${BUYER_EMAIL}','seed-hash','BUYER','ACTIVE'),
  ('${SELLER_USER_ID}','${SELLER_EMAIL}','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name) VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Checkout Mixed Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${PRODUCT_OK_ID}','${SELLER_ID}','Available ${CASE_SUFFIX}','Available mixed item','widgets',1000,5,TRUE,'ACTIVE'),
  ('${PRODUCT_BAD_ID}','${SELLER_ID}','Sold Out ${CASE_SUFFIX}','Unavailable mixed item','widgets',500,0,TRUE,'SOLD_OUT');
SQL
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'BUYER', status: 'ACTIVE'}, process.argv[3]));" "$BUYER_ID" "$BUYER_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_OK_ID}\",\"qty\":1},{\"product_id\":\"${PRODUCT_BAD_ID}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
jq -e --arg msg "Product ${PRODUCT_BAD_ID} unavailable" '.error == $msg' "$RESPONSE_FILE" >/dev/null
ORDER_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM orders WHERE buyer_id = '${BUYER_ID}';")"
STOCK_OK="$(psql "$DATABASE_URL" -t -A -c "SELECT stock_qty FROM products WHERE id = '${PRODUCT_OK_ID}';")"
[ "$ORDER_COUNT" = "0" ]
[ "$STOCK_OK" = "5" ]

echo "CODEVALID_TEST_ASSERTION_OK:checkout_mixed_availability_items"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PRODUCT_OK_ID}','${PRODUCT_BAD_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id IN ('${BUYER_ID}','${SELLER_USER_ID}') OR email IN ('${BUYER_EMAIL}','${SELLER_EMAIL}');" >/dev/null
