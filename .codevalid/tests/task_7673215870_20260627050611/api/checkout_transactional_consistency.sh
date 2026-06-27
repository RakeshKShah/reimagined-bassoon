#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="user-buyer-tx-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-tx-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="user-seller-tx-${CASE_SUFFIX}"
SELLER_EMAIL="seller-tx-${CASE_SUFFIX}@example.com"
SELLER_PROFILE_ID="seller-profile-tx-${CASE_SUFFIX}"
PRODUCT_ID="prod-500-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/checkout_transactional_consistency_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_transactional_consistency_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'BUYER', status: 'ACTIVE'}, process.argv[3]));" "$BUYER_ID" "$BUYER_EMAIL" "$JWT_SECRET")"

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "productId" = '$PRODUCT_ID';
DELETE FROM "Order" WHERE "buyerId" = '$BUYER_ID';
DELETE FROM "Product" WHERE id = '$PRODUCT_ID';
DELETE FROM "SellerProfile" WHERE id = '$SELLER_PROFILE_ID';
DELETE FROM "User" WHERE id IN ('$BUYER_ID', '$SELLER_USER_ID');
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('$BUYER_ID', '$BUYER_EMAIL', 'hashed-password', 'BUYER', 'ACTIVE', NOW()),
  ('$SELLER_USER_ID', '$SELLER_EMAIL', 'hashed-password', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('$SELLER_PROFILE_ID', '$SELLER_USER_ID', 'Store ${CASE_SUFFIX}', 'Transactional seller', 'ACTIVE', NOW());
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", status, visible, "createdAt") VALUES
  ('$PRODUCT_ID', '$SELLER_PROFILE_ID', 'Atomic Product ${CASE_SUFFIX}', 'Transactional consistency product', 'ART', 1000, 2, 'ACTIVE', true, NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data "{\"items\":[{\"product_id\":\"$PRODUCT_ID\",\"qty\":2}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"status":"PAID"' "$RESPONSE_FILE" >/dev/null
grep -F '"totalCents":2000' "$RESPONSE_FILE" >/dev/null
ORDER_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM \"Order\" WHERE \"buyerId\" = '$BUYER_ID' ORDER BY \"createdAt\" DESC LIMIT 1;")"
PRODUCT_STOCK="$(psql "$DATABASE_URL" -t -A -c "SELECT \"stockQty\" FROM \"Product\" WHERE id = '$PRODUCT_ID';")"
PRODUCT_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM \"Product\" WHERE id = '$PRODUCT_ID';")"
[ "$ORDER_STATUS" = "PAID" ]
[ "$PRODUCT_STOCK" = "0" ]
[ "$PRODUCT_STATUS" = "SOLD_OUT" ]
echo "CODEVALID_TEST_ASSERTION_OK:checkout_transactional_consistency"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "productId" = '$PRODUCT_ID';
DELETE FROM "Order" WHERE "buyerId" = '$BUYER_ID';
DELETE FROM "Product" WHERE id = '$PRODUCT_ID';
DELETE FROM "SellerProfile" WHERE id = '$SELLER_PROFILE_ID';
DELETE FROM "User" WHERE id IN ('$BUYER_ID', '$SELLER_USER_ID');
SQL
