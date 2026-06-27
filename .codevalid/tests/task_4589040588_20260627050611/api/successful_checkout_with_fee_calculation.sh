#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-123-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-fee-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="seller-user-789-${CASE_SUFFIX}"
SELLER_EMAIL="seller-fee-${CASE_SUFFIX}@example.com"
SELLER_ID="seller-789-${CASE_SUFFIX}"
PRODUCT_ID="prod-456-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/successful_checkout_with_fee_calculation_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/successful_checkout_with_fee_calculation_${CASE_SUFFIX}.status"
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
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Seller Fee Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES ('${PRODUCT_ID}','${SELLER_ID}','Fee Widget ${CASE_SUFFIX}','Checkout fee calculation product','widgets',1000,10,TRUE,'ACTIVE');
SQL
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'BUYER', status: 'ACTIVE'}, process.argv[3]));" "$BUYER_ID" "$BUYER_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_ID}\",\"qty\":2}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg product_id "$PRODUCT_ID" --arg seller_id "$SELLER_ID" '
  .status == "PAID" and
  .totalCents == 2000 and
  .platformFeeCents == 200 and
  (.items | length) == 1 and
  .items[0].productId == $product_id and
  .items[0].sellerId == $seller_id and
  .items[0].qty == 2 and
  .items[0].priceAtPurchase == 1000 and
  .items[0].sellerPayoutCents == 1800
' "$RESPONSE_FILE" >/dev/null
STOCK_QTY="$(psql "$DATABASE_URL" -t -A -c "SELECT stock_qty FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$STOCK_QTY" = "8" ]

echo "CODEVALID_TEST_ASSERTION_OK:successful_checkout_with_fee_calculation"

# Cleanup
ORDER_ID="$(jq -r '.id // empty' "$RESPONSE_FILE")"
if [ -n "$ORDER_ID" ]; then
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE order_id = '${ORDER_ID}'; DELETE FROM orders WHERE id = '${ORDER_ID}';" >/dev/null
fi
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id IN ('${BUYER_ID}','${SELLER_USER_ID}') OR email IN ('${BUYER_EMAIL}','${SELLER_EMAIL}');" >/dev/null
