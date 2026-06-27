#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-nullbio-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-nullbio-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="user-nobio-${CASE_SUFFIX}"
SELLER_ID="seller-nobio-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/admin_views_seller_with_null_bio_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_views_seller_with_null_bio_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"ADMIN",status:"ACTIVE"}, process.argv[3], {expiresIn:"7d"}));' "$ADMIN_ID" "$ADMIN_EMAIL" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${ADMIN_ID}', '${SELLER_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create admin and a seller profile whose bio is null
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', 'seed-hash', 'ADMIN', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'minimal-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', TIMESTAMPTZ '2024-01-20T10:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio, created_at)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Basic Store', NULL, TIMESTAMPTZ '2024-01-20T10:00:00Z');
SQL

# When — admin requests the seller list
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — seller is returned successfully and bio is null
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"${SELLER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"email":"minimal-' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Basic Store"' "$RESPONSE_FILE" >/dev/null
node -e '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const sellerId = process.argv[2];
const seller = Array.isArray(body) ? body.find((s) => s.id === sellerId) : null;
if (!seller) process.exit(1);
if (seller.bio !== null) process.exit(1);
' "$RESPONSE_FILE" "$SELLER_ID"

echo "CODEVALID_TEST_ASSERTION_OK:admin_views_seller_with_null_bio"

# Cleanup — handled by trap to remove seeded rows
