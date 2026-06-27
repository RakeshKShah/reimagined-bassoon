#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-suspended-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-suspended-${CASE_SUFFIX}@example.com"
SUSPENDED_USER_ID="user-sus-${CASE_SUFFIX}"
ACTIVE_USER_ID="user-act-${CASE_SUFFIX}"
SUSPENDED_SELLER_ID="seller-suspended-${CASE_SUFFIX}"
ACTIVE_SELLER_ID="seller-active-${CASE_SUFFIX}"
SUSPENDED_PRODUCT_ID="prod-hidden-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/admin_views_sellers_includes_suspended_status_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_views_sellers_includes_suspended_status_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"ADMIN",status:"ACTIVE"}, process.argv[3], {expiresIn:"7d"}));' "$ADMIN_ID" "$ADMIN_EMAIL" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${SUSPENDED_PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id IN ('${SUSPENDED_SELLER_ID}', '${ACTIVE_SELLER_ID}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${ADMIN_ID}', '${SUSPENDED_USER_ID}', '${ACTIVE_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create admin, a suspended seller with a hidden listing, and an active seller
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', 'seed-hash', 'ADMIN', 'ACTIVE', NOW()),
  ('${SUSPENDED_USER_ID}', 'suspended-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'SUSPENDED', TIMESTAMPTZ '2024-01-05T12:00:00Z'),
  ('${ACTIVE_USER_ID}', 'active-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', TIMESTAMPTZ '2024-01-20T14:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio, created_at)
VALUES
  ('${SUSPENDED_SELLER_ID}', '${SUSPENDED_USER_ID}', 'Banned Store', 'This store was suspended', TIMESTAMPTZ '2024-01-05T12:00:00Z'),
  ('${ACTIVE_SELLER_ID}', '${ACTIVE_USER_ID}', 'Active Store', 'Still operating', TIMESTAMPTZ '2024-01-20T14:00:00Z');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at)
VALUES ('${SUSPENDED_PRODUCT_ID}', '${SUSPENDED_SELLER_ID}', 'Policy Violation Item', 'Hidden from buyers', 'General', 999, 1, ARRAY['https://example.com/hidden.jpg'], 'ACTIVE', false, NOW(), NOW());
SQL

# When — admin requests all sellers
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — suspended sellers are still present in the admin response
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"${SUSPENDED_SELLER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SUSPENDED"' "$RESPONSE_FILE" >/dev/null
grep -F '"email":"suspended-' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Banned Store"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"${ACTIVE_SELLER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
node -e '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const suspendedId = process.argv[2];
const activeId = process.argv[3];
if (!Array.isArray(body) || body.length < 2) process.exit(1);
const suspended = body.find((s) => s.id === suspendedId);
const active = body.find((s) => s.id === activeId);
if (!suspended || suspended.status !== "SUSPENDED") process.exit(1);
if (!active || active.status !== "ACTIVE") process.exit(1);
' "$RESPONSE_FILE" "$SUSPENDED_SELLER_ID" "$ACTIVE_SELLER_ID"

echo "CODEVALID_TEST_ASSERTION_OK:admin_views_sellers_includes_suspended_status"

# Cleanup — handled by trap to remove seeded rows
