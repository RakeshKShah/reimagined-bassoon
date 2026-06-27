#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-multi-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-multi-${CASE_SUFFIX}@example.com"
SELLER1_USER_ID="seller1-user-${CASE_SUFFIX}"
SELLER1_EMAIL="seller1-${CASE_SUFFIX}@example.com"
SELLER1_ID="seller-1-${CASE_SUFFIX}"
SELLER2_USER_ID="seller2-user-${CASE_SUFFIX}"
SELLER2_EMAIL="seller2-${CASE_SUFFIX}@example.com"
SELLER2_ID="seller-2-${CASE_SUFFIX}"
PRODUCT_A_ID="prod-a-${CASE_SUFFIX}"
PRODUCT_B_ID="prod-b-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/multiple_products_checkout_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/multiple_products_checkout_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${PRODUCT_A_ID}','${PRODUCT_B_ID}');
DELETE FROM orders WHERE buyer_id = '${BUYER_ID}';
DELETE FROM products WHERE id IN ('${PRODUCT_A_ID}','${PRODUCT_B_ID}');
DELETE FROM sellers WHERE id IN ('${SELLER1_ID}','${SELLER2_ID}');
DELETE FROM users WHERE id IN ('${BUYER_ID}','${SELLER1_USER_ID}','${SELLER2_USER_ID}') OR email IN ('${BUYER_EMAIL}','${SELLER1_EMAIL}','${SELLER2_EMAIL}');
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${BUYER_ID}','${BUYER_EMAIL}','seed-hash','BUYER','ACTIVE'),
  ('${SELLER1_USER_ID}','${SELLER1_EMAIL}','seed-hash','SELLER','ACTIVE'),
  ('${SELLER2_USER_ID}','${SELLER2_EMAIL}','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES
  ('${SELLER1_ID}','${SELLER1_USER_ID}','Store A ${CASE_SUFFIX}'),
  ('${SELLER2_ID}','${SELLER2_USER_ID}','Store B ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${PRODUCT_A_ID}','${SELLER1_ID}','Product A ${CASE_SUFFIX}','Multi checkout product A','widgets',1000,5,TRUE,'ACTIVE'),
  ('${PRODUCT_B_ID}','${SELLER2_ID}','Product B ${CASE_SUFFIX}','Multi checkout product B','widgets',2000,3,TRUE,'ACTIVE');
SQL
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'BUYER', status: 'ACTIVE'}, process.argv[3]));" "$BUYER_ID" "$BUYER_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_A_ID}\",\"qty\":2},{\"product_id\":\"${PRODUCT_B_ID}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg product_a "$PRODUCT_A_ID" --arg product_b "$PRODUCT_B_ID" '
  .status == "PAID" and
  .totalCents == 4000 and
  .platformFeeCents == 400 and
  (.items | length) == 2 and
  ([.items[].productId] | index($product_a)) != null and
  ([.items[].productId] | index($product_b)) != null and
  ([.items[] | select(.productId == $product_a) | .sellerPayoutCents] | first) == 1800 and
  ([.items[] | select(.productId == $product_b) | .sellerPayoutCents] | first) == 1800
' "$RESPONSE_FILE" >/dev/null
STOCK_A="$(psql "$DATABASE_URL" -t -A -c "SELECT stock_qty FROM products WHERE id = '${PRODUCT_A_ID}';")"
STOCK_B="$(psql "$DATABASE_URL" -t -A -c "SELECT stock_qty FROM products WHERE id = '${PRODUCT_B_ID}';")"
[ "$STOCK_A" = "3" ]
[ "$STOCK_B" = "2" ]

echo "CODEVALID_TEST_ASSERTION_OK:multiple_products_checkout"

# Cleanup
ORDER_ID="$(jq -r '.id // empty' "$RESPONSE_FILE")"
if [ -n "$ORDER_ID" ]; then
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE order_id = '${ORDER_ID}'; DELETE FROM orders WHERE id = '${ORDER_ID}';" >/dev/null
fi
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PRODUCT_A_ID}','${PRODUCT_B_ID}'); DELETE FROM sellers WHERE id IN ('${SELLER1_ID}','${SELLER2_ID}'); DELETE FROM users WHERE id IN ('${BUYER_ID}','${SELLER1_USER_ID}','${SELLER2_USER_ID}') OR email IN ('${BUYER_EMAIL}','${SELLER1_EMAIL}','${SELLER2_EMAIL}');" >/dev/null
