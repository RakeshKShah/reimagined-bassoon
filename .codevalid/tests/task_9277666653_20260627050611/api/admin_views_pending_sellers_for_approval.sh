#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-pending-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-pending-${CASE_SUFFIX}@example.com"
PENDING_USER_ID="user-pend-${CASE_SUFFIX}"
APPROVED_USER_ID="user-app-${CASE_SUFFIX}"
PENDING_SELLER_ID="seller-pending-${CASE_SUFFIX}"
APPROVED_SELLER_ID="seller-approved-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/admin_views_pending_sellers_for_approval_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_views_pending_sellers_for_approval_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"ADMIN",status:"ACTIVE"}, process.argv[3], {expiresIn:"7d"}));' "$ADMIN_ID" "$ADMIN_EMAIL" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id IN ('${PENDING_SELLER_ID}', '${APPROVED_SELLER_ID}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${ADMIN_ID}', '${PENDING_USER_ID}', '${APPROVED_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create admin, a pending seller awaiting approval, and an approved seller
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', 'seed-hash', 'ADMIN', 'ACTIVE', NOW()),
  ('${PENDING_USER_ID}', 'pending-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'PENDING', TIMESTAMPTZ '2024-01-18T09:00:00Z'),
  ('${APPROVED_USER_ID}', 'approved-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', TIMESTAMPTZ '2024-01-10T11:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio, created_at)
VALUES
  ('${PENDING_SELLER_ID}', '${PENDING_USER_ID}', 'New Applicant', 'Awaiting approval', TIMESTAMPTZ '2024-01-18T09:00:00Z'),
  ('${APPROVED_SELLER_ID}', '${APPROVED_USER_ID}', 'Established Store', 'Approved seller', TIMESTAMPTZ '2024-01-10T11:00:00Z');
SQL

# When — admin requests the seller list
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — pending sellers are included and identifiable by status
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"${PENDING_SELLER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
grep -F '"email":"pending-' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"New Applicant"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"${APPROVED_SELLER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
node -e '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const pendingId = process.argv[2];
if (!Array.isArray(body) || body.length < 2) process.exit(1);
const pending = body.find((s) => s.id === pendingId);
if (!pending || pending.status !== "PENDING" || pending.store_name !== "New Applicant") process.exit(1);
' "$RESPONSE_FILE" "$PENDING_SELLER_ID"

echo "CODEVALID_TEST_ASSERTION_OK:admin_views_pending_sellers_for_approval"

# Cleanup — handled by trap to remove seeded rows
