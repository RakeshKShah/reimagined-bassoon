#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-empty-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-empty-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/admin_views_sellers_empty_list_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_views_sellers_empty_list_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"ADMIN",status:"ACTIVE"}, process.argv[3], {expiresIn:"7d"}));' "$ADMIN_ID" "$ADMIN_EMAIL" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${ADMIN_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create an authenticated admin and ensure this test seeds no seller profiles
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', 'seed-hash', 'ADMIN', 'ACTIVE', NOW());
SQL

# When — admin requests the seller list
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — response succeeds and returns an empty JSON array
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
node -e '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(body)) process.exit(1);
if (body.length !== 0) process.exit(1);
' "$RESPONSE_FILE"

echo "CODEVALID_TEST_ASSERTION_OK:admin_views_sellers_empty_list"

# Cleanup — handled by trap to remove seeded rows
