#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-orphan-${CASE_SUFFIX}"
EMAIL="seller-orphan-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/seller_profile_not_found_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_profile_not_found_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE"}, process.argv[3], {expiresIn:"7d"}));' "$USER_ID" "$EMAIL" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create an approved seller without a seller profile
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('${USER_ID}', '${EMAIL}', 'seed-hash', 'SELLER', 'ACTIVE', NOW());" >/dev/null

# When — load seller dashboard without an associated seller profile
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — verify missing seller profile returns 404
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Seller profile not found"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_profile_not_found"

# Cleanup — handled by trap to delete seeded user
