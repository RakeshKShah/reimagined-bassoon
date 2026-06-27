#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="user-buyer-9-${CASE_SUFFIX}"
BUYER_EMAIL="checkout-price-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="seller-user-9-${CASE_SUFFIX}"
SELLER_EMAIL="checkout-price-seller-${CASE_SUFFIX}@example.com"
SELLER_ID="seller-9-${CASE_SUFFIX}"
PRODUCT_ID="prod-onsale-33-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/checkout_price_snapshot_saved_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_price_snapshot_saved_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id = '${PRODUCT_ID}';
DELETE FROM orders WHERE buyer_id = '${BUYER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${BUYER_ID}','${SELLER_USER_ID}') OR email IN ('${BUYER_EMAIL}','${SELLER_EMAIL}');
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${BUYER_ID}','${BUYER_EMAIL}','seed-hash','BUYER','ACTIVE'),
  ('${SELLER_USER_ID}','${SELLER_EMAIL}','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name) VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Checkout Price Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES ('${PRODUCT_ID}','${SELLER_ID}','On Sale ${CASE_SUFFIX}','Price snapshot verification product','widgets',1200,10,TRUE,'ACTIVE');
SQL
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'BUYER', status: 'ACTIVE'}, process.argv[3]));" "$BUYER_ID" "$BUYER_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_ID}\",\"qty\":1}]}" > "$STATUS_FILE"
psql "$DATABASE_URL" -c "UPDATE products SET price_cents = 999 WHERE id = '${PRODUCT_ID}';" >/dev/null

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg product_id "$PRODUCT_ID" '
  .status == "PAID" and
  .items[0].productId == $product_id and
  .items[0].priceAtPurchase == 1200
' "$RESPONSE_FILE" >/dev/null
ORDER_ID="$(jq -r '.id' "$RESPONSE_FILE")"
SNAPSHOT_PRICE="$(psql "$DATABASE_URL" -t -A -c "SELECT price_at_purchase FROM order_items WHERE order_id = '${ORDER_ID}' AND product_id = '${PRODUCT_ID}';")"
CURRENT_PRICE="$(psql "$DATABASE_URL" -t -A -c "SELECT price_cents FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$SNAPSHOT_PRICE" = "1200" ]
[ "$CURRENT_PRICE" = "999" ]

echo "CODEVALID_TEST_ASSERTION_OK:checkout_price_snapshot_saved"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE order_id = '${ORDER_ID}'; DELETE FROM orders WHERE id = '${ORDER_ID}'; DELETE FROM products WHERE id = '${PRODUCT_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id IN ('${BUYER_ID}','${SELLER_USER_ID}') OR email IN ('${BUYER_EMAIL}','${SELLER_EMAIL}');" >/dev/null
