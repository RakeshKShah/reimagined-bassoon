#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-views-all-${CASE_SUFFIX}"
ADMIN_EMAIL="admin-views-all-${CASE_SUFFIX}@example.com"
SELLER_ONE_USER_ID="user-456-${CASE_SUFFIX}"
SELLER_TWO_USER_ID="user-789-${CASE_SUFFIX}"
SELLER_ONE_ID="seller-123-${CASE_SUFFIX}"
SELLER_TWO_ID="seller-456-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/admin_views_all_sellers_successfully_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_views_all_sellers_successfully_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"ADMIN",status:"ACTIVE"}, process.argv[3], {expiresIn:"7d"}));' "$ADMIN_ID" "$ADMIN_EMAIL" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE seller_id IN ('${SELLER_ONE_ID}', '${SELLER_TWO_ID}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id IN ('${SELLER_ONE_ID}', '${SELLER_TWO_ID}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${ADMIN_ID}', '${SELLER_ONE_USER_ID}', '${SELLER_TWO_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create authenticated admin and two sellers with different creation dates and product counts
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', 'seed-hash', 'ADMIN', 'ACTIVE', NOW()),
  ('${SELLER_ONE_USER_ID}', 'store1-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE', TIMESTAMPTZ '2024-01-15T10:00:00Z'),
  ('${SELLER_TWO_USER_ID}', 'store2-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'PENDING', TIMESTAMPTZ '2024-01-10T08:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio, created_at)
VALUES
  ('${SELLER_ONE_ID}', '${SELLER_ONE_USER_ID}', 'Garden Supplies', 'Quality garden products', TIMESTAMPTZ '2024-01-15T10:00:00Z'),
  ('${SELLER_TWO_ID}', '${SELLER_TWO_USER_ID}', 'Tech Gadgets', 'Latest tech', TIMESTAMPTZ '2024-01-10T08:00:00Z');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at)
VALUES
  ('prod-s1a-${CASE_SUFFIX}', '${SELLER_ONE_ID}', 'Shovel', 'Garden shovel', 'Garden', 2500, 10, ARRAY['https://example.com/shovel.jpg'], 'ACTIVE', true, NOW(), NOW()),
  ('prod-s1b-${CASE_SUFFIX}', '${SELLER_ONE_ID}', 'Rake', 'Leaf rake', 'Garden', 1800, 8, ARRAY['https://example.com/rake.jpg'], 'ACTIVE', true, NOW(), NOW()),
  ('prod-s1c-${CASE_SUFFIX}', '${SELLER_ONE_ID}', 'Hose', 'Water hose', 'Garden', 3200, 5, ARRAY['https://example.com/hose.jpg'], 'ACTIVE', true, NOW(), NOW()),
  ('prod-s1d-${CASE_SUFFIX}', '${SELLER_ONE_ID}', 'Gloves', 'Garden gloves', 'Garden', 900, 20, ARRAY['https://example.com/gloves.jpg'], 'ACTIVE', true, NOW(), NOW()),
  ('prod-s1e-${CASE_SUFFIX}', '${SELLER_ONE_ID}', 'Seeds', 'Flower seeds', 'Garden', 500, 30, ARRAY['https://example.com/seeds.jpg'], 'ACTIVE', true, NOW(), NOW());
SQL

# When — admin requests the seller list
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — response includes both sellers with expected fields, counts, and descending creation order
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"${SELLER_ONE_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"user_id":"'"${SELLER_ONE_USER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"email":"store1-' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Garden Supplies"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Quality garden products"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"product_count":5' "$RESPONSE_FILE" >/dev/null
grep -F '"created_at":"2024-01-15T10:00:00.000Z"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"${SELLER_TWO_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"user_id":"'"${SELLER_TWO_USER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"email":"store2-' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Tech Gadgets"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Latest tech"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
grep -F '"product_count":0' "$RESPONSE_FILE" >/dev/null
grep -F '"created_at":"2024-01-10T08:00:00.000Z"' "$RESPONSE_FILE" >/dev/null
node -e '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const sellerOneId = process.argv[2];
const sellerTwoId = process.argv[3];
if (!Array.isArray(body) || body.length < 2) process.exit(1);
if (body[0].id !== sellerOneId) process.exit(1);
if (body[0].product_count !== 5) process.exit(1);
if (body[0].status !== "ACTIVE") process.exit(1);
if (body[1].id !== sellerTwoId) process.exit(1);
if (body[1].product_count !== 0) process.exit(1);
if (body[1].status !== "PENDING") process.exit(1);
' "$RESPONSE_FILE" "$SELLER_ONE_ID" "$SELLER_TWO_ID"

echo "CODEVALID_TEST_ASSERTION_OK:admin_views_all_sellers_successfully"

# Cleanup — handled by trap to remove seeded rows
