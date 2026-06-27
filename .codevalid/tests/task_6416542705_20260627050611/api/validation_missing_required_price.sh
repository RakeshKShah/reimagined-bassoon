#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-missing-price-${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp-missing-price-${CASE_SUFFIX}"
EMAIL="seller-missing-price-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/validation_missing_required_price_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/validation_missing_required_price_${CASE_SUFFIX}.status"
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

# Given — create an approved seller with a profile
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('${USER_ID}', '${EMAIL}', 'seed-hash', 'SELLER', 'ACTIVE', NOW());"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_PROFILE_ID}', '${USER_ID}', 'Validation Store ${CASE_SUFFIX}', 'Validation bio');"

# When — submit a payload missing price_cents
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"No Price Product","description":"Missing price test","category":"Test","stock_qty":5,"photos":[]}' > "$STATUS_FILE"

# Then — verify schema validation rejects the request
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:validation_missing_required_price"

# Cleanup — handled by trap to delete seeded profile and user
