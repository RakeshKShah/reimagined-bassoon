#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="buyer-product-${CASE_SUFFIX}"
EMAIL="buyer-product-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/unauthorized_non_seller_role_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/unauthorized_non_seller_role_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"BUYER",status:"ACTIVE"}, process.argv[3], {expiresIn:"7d"}));' "$USER_ID" "$EMAIL" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create an authenticated buyer user
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('${USER_ID}', '${EMAIL}', 'seed-hash', 'BUYER', 'ACTIVE', NOW());"

# When — attempt to create a product as a non-seller
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"Test Product","description":"Test","category":"Test","price_cents":1000,"stock_qty":5,"photos":[]}' > "$STATUS_FILE"

# Then — verify seller-only access is enforced
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Seller access required"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:unauthorized_non_seller_role"

# Cleanup — handled by trap to delete seeded user
