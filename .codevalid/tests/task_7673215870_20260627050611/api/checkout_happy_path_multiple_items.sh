#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="user-buyer-1-${CASE_SUFFIX}"
BUYER_EMAIL="buyer1-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="user-seller-1-${CASE_SUFFIX}"
SELLER_EMAIL="seller1-${CASE_SUFFIX}@example.com"
SELLER_PROFILE_ID="seller-profile-1-${CASE_SUFFIX}"
PROD_100_ID="prod-100-${CASE_SUFFIX}"
PROD_200_ID="prod-200-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/checkout_happy_path_multiple_items_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_happy_path_multiple_items_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'BUYER', status: 'ACTIVE'}, process.argv[3]));" "$BUYER_ID" "$BUYER_EMAIL" "$JWT_SECRET")"

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "productId" IN ('$PROD_100_ID', '$PROD_200_ID');
DELETE FROM "Order" WHERE "buyerId" = '$BUYER_ID';
DELETE FROM "Product" WHERE id IN ('$PROD_100_ID', '$PROD_200_ID');
DELETE FROM "SellerProfile" WHERE id = '$SELLER_PROFILE_ID';
DELETE FROM "User" WHERE id IN ('$BUYER_ID', '$SELLER_USER_ID');
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('$BUYER_ID', '$BUYER_EMAIL', 'hashed-password', 'BUYER', 'ACTIVE', NOW()),
  ('$SELLER_USER_ID', '$SELLER_EMAIL', 'hashed-password', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('$SELLER_PROFILE_ID', '$SELLER_USER_ID', 'Store ${CASE_SUFFIX}', 'Test seller', 'ACTIVE', NOW());
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", status, visible, "createdAt") VALUES
  ('$PROD_100_ID', '$SELLER_PROFILE_ID', 'Widget 100 ${CASE_SUFFIX}', 'Happy path product 100', 'HOME', 500, 10, 'ACTIVE', true, NOW()),
  ('$PROD_200_ID', '$SELLER_PROFILE_ID', 'Widget 200 ${CASE_SUFFIX}', 'Happy path product 200', 'ART', 1200, 5, 'ACTIVE', true, NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data "{\"items\":[{\"product_id\":\"$PROD_100_ID\",\"qty\":2},{\"product_id\":\"$PROD_200_ID\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"status":"PAID"' "$RESPONSE_FILE" >/dev/null
grep -F '"totalCents":2200' "$RESPONSE_FILE" >/dev/null
grep -F '"productId":"'$PROD_100_ID'"' "$RESPONSE_FILE" >/dev/null
grep -F '"productId":"'$PROD_200_ID'"' "$RESPONSE_FILE" >/dev/null
grep -F '"qty":2' "$RESPONSE_FILE" >/dev/null
grep -F '"qty":1' "$RESPONSE_FILE" >/dev/null
STOCK_100="$(psql "$DATABASE_URL" -t -A -c "SELECT \"stockQty\" FROM \"Product\" WHERE id = '$PROD_100_ID';")"
STOCK_200="$(psql "$DATABASE_URL" -t -A -c "SELECT \"stockQty\" FROM \"Product\" WHERE id = '$PROD_200_ID';")"
[ "$STOCK_100" = "8" ]
[ "$STOCK_200" = "4" ]
ORDER_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM \"Order\" WHERE \"buyerId\" = '$BUYER_ID' AND status = 'PAID' AND \"totalCents\" = 2200;")"
[ "$ORDER_COUNT" = "1" ]
echo "CODEVALID_TEST_ASSERTION_OK:checkout_happy_path_multiple_items"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "productId" IN ('$PROD_100_ID', '$PROD_200_ID');
DELETE FROM "Order" WHERE "buyerId" = '$BUYER_ID';
DELETE FROM "Product" WHERE id IN ('$PROD_100_ID', '$PROD_200_ID');
DELETE FROM "SellerProfile" WHERE id = '$SELLER_PROFILE_ID';
DELETE FROM "User" WHERE id IN ('$BUYER_ID', '$SELLER_USER_ID');
SQL
