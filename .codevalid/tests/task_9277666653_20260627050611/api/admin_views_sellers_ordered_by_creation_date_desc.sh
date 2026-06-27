#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-order-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-order-${CASE_SUFFIX}@example.com"
OLD_USER_ID="user-old-${CASE_SUFFIX}"
MIDDLE_USER_ID="user-middle-${CASE_SUFFIX}"
NEW_USER_ID="user-new-${CASE_SUFFIX}"
OLD_SELLER_ID="seller-old-${CASE_SUFFIX}"
MIDDLE_SELLER_ID="seller-middle-${CASE_SUFFIX}"
NEW_SELLER_ID="seller-new-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/admin_views_sellers_ordered_by_creation_date_desc_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_views_sellers_ordered_by_creation_date_desc_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"ADMIN",status:"ACTIVE"}, process.argv[3], {expiresIn:"7d"}));' "$ADMIN_ID" "$ADMIN_EMAIL" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id IN ('${OLD_SELLER_ID}', '${MIDDLE_SELLER_ID}', '${NEW_SELLER_ID}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${ADMIN_ID}', '${OLD_USER_ID}', '${MIDDLE_USER_ID}', '${NEW_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create three sellers with ascending creation timestamps
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', 'seed-hash', 'ADMIN', 'ACTIVE', NOW()),
  ('${OLD_USER_ID}', 'old-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', TIMESTAMPTZ '2024-01-01T08:00:00Z'),
  ('${MIDDLE_USER_ID}', 'middle-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', TIMESTAMPTZ '2024-01-15T08:00:00Z'),
  ('${NEW_USER_ID}', 'new-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', TIMESTAMPTZ '2024-01-25T08:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio, created_at)
VALUES
  ('${OLD_SELLER_ID}', '${OLD_USER_ID}', 'Old Store', 'Oldest seller', TIMESTAMPTZ '2024-01-01T08:00:00Z'),
  ('${MIDDLE_SELLER_ID}', '${MIDDLE_USER_ID}', 'Middle Store', 'Middle seller', TIMESTAMPTZ '2024-01-15T08:00:00Z'),
  ('${NEW_SELLER_ID}', '${NEW_USER_ID}', 'New Store', 'Newest seller', TIMESTAMPTZ '2024-01-25T08:00:00Z');
SQL

# When — admin requests the seller list
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — sellers appear in descending order by associated user creation time
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"created_at":"2024-01-25T08:00:00.000Z"' "$RESPONSE_FILE" >/dev/null
grep -F '"created_at":"2024-01-15T08:00:00.000Z"' "$RESPONSE_FILE" >/dev/null
grep -F '"created_at":"2024-01-01T08:00:00.000Z"' "$RESPONSE_FILE" >/dev/null
node -e '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const newest = process.argv[2];
const middle = process.argv[3];
const oldest = process.argv[4];
if (!Array.isArray(body) || body.length < 3) process.exit(1);
const idxNew = body.findIndex((s) => s.id === newest);
const idxMiddle = body.findIndex((s) => s.id === middle);
const idxOld = body.findIndex((s) => s.id === oldest);
if (idxNew === -1 || idxMiddle === -1 || idxOld === -1) process.exit(1);
if (!(idxNew < idxMiddle && idxMiddle < idxOld)) process.exit(1);
' "$RESPONSE_FILE" "$NEW_SELLER_ID" "$MIDDLE_SELLER_ID" "$OLD_SELLER_ID"

echo "CODEVALID_TEST_ASSERTION_OK:admin_views_sellers_ordered_by_creation_date_desc"

# Cleanup — handled by trap to remove seeded rows
