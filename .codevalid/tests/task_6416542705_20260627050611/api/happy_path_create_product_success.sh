#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-happy-${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp-happy-${CASE_SUFFIX}"
EMAIL="seller-happy-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/happy_path_create_product_success_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/happy_path_create_product_success_${CASE_SUFFIX}.status"
PRODUCT_TITLE="Vintage Camera ${CASE_SUFFIX}"
PRODUCT_DESCRIPTION="Classic 35mm camera"
PRODUCT_CATEGORY="Electronics"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE",sellerProfileId:process.argv[3]}, process.argv[4], {expiresIn:"7d"}));' "$USER_ID" "$EMAIL" "$SELLER_PROFILE_ID" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE seller_id = '${SELLER_PROFILE_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}' OR user_id = '${USER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create an approved seller and seller profile for an authenticated request
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('${USER_ID}', '${EMAIL}', 'seed-hash', 'SELLER', 'ACTIVE', NOW());"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_PROFILE_ID}', '${USER_ID}', 'Store ${CASE_SUFFIX}', 'Bio ${CASE_SUFFIX}');"

# When — create a product as the approved seller
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"'"$PRODUCT_TITLE"'","description":"'"$PRODUCT_DESCRIPTION"'","category":"'"$PRODUCT_CATEGORY"'","price_cents":29999,"stock_qty":10,"photos":["https://example.com/photo1.jpg"]}' > "$STATUS_FILE"

# Then — verify 201 and returned product fields
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
grep -F '"sellerId":"'"$SELLER_PROFILE_ID"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"title":"'"$PRODUCT_TITLE"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"description":"'"$PRODUCT_DESCRIPTION"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"category":"'"$PRODUCT_CATEGORY"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"priceCents":29999' "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":10' "$RESPONSE_FILE" >/dev/null
grep -F '"photos":["https://example.com/photo1.jpg"]' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"visible":true' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:happy_path_create_product_success"

# Cleanup — handled by trap to remove created product, seller profile, and user
