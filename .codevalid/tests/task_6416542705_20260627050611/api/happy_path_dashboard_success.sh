#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-dashboard-${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp-dashboard-${CASE_SUFFIX}"
PRODUCT_ID_NEWER="prod-croissant-${CASE_SUFFIX}"
PRODUCT_ID_OLDER="prod-muffin-${CASE_SUFFIX}"
ORDER_ID="ord-dashboard-${CASE_SUFFIX}"
ORDER_ITEM_ID="oi-dashboard-${CASE_SUFFIX}"
BUYER_ID="buyer-dashboard-${CASE_SUFFIX}"
SELLER_EMAIL="seller-dashboard-${CASE_SUFFIX}@example.com"
BUYER_EMAIL="buyer-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/happy_path_dashboard_success_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/happy_path_dashboard_success_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE",sellerProfileId:process.argv[3]}, process.argv[4], {expiresIn:"7d"}));' "$USER_ID" "$SELLER_EMAIL" "$SELLER_PROFILE_ID" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id = '${ORDER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PRODUCT_ID_NEWER}', '${PRODUCT_ID_OLDER}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}', '${BUYER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create active seller, store profile, products, buyer, order, and order item
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${USER_ID}', '${SELLER_EMAIL}', 'seed-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio, created_at)
VALUES ('${SELLER_PROFILE_ID}', '${USER_ID}', 'Fresh Bakes', 'Artisanal pastries', NOW());
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at)
VALUES
  ('${PRODUCT_ID_NEWER}', '${SELLER_PROFILE_ID}', 'Croissant', 'Buttery pastry', 'Bakery', 650, 12, ARRAY['https://example.com/croissant.jpg'], 'ACTIVE', true, TIMESTAMPTZ '2024-01-10T09:00:00Z', NOW()),
  ('${PRODUCT_ID_OLDER}', '${SELLER_PROFILE_ID}', 'Muffin', 'Blueberry muffin', 'Bakery', 450, 8, ARRAY['https://example.com/muffin.jpg'], 'ACTIVE', true, TIMESTAMPTZ '2024-01-09T08:00:00Z', NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', 'seed-hash', 'BUYER', 'ACTIVE', NOW());
INSERT INTO orders (id, buyer_id, status, subtotal_cents, fee_cents, total_cents, created_at, updated_at)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'PAID', 650, 0, 650, TIMESTAMPTZ '2024-01-12T11:00:00Z', NOW());
INSERT INTO order_items (id, order_id, product_id, qty, unit_price_cents, seller_payout_cents, created_at)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID_NEWER}', 2, 650, 500, TIMESTAMPTZ '2024-01-12T11:00:00Z');
SQL

# When — load seller dashboard
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — verify dashboard payload includes store profile, ordered products, order mapping, and earnings
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"store_name":"Fresh Bakes"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Artisanal pastries"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"${ORDER_ITEM_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"order_id":"'"${ORDER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"product_title":"Croissant"' "$RESPONSE_FILE" >/dev/null
grep -F '"qty":2' "$RESPONSE_FILE" >/dev/null
grep -F '"buyer_email":"'"${BUYER_EMAIL}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"order_status":"PAID"' "$RESPONSE_FILE" >/dev/null
grep -F '"seller_payout_cents":500' "$RESPONSE_FILE" >/dev/null
grep -F '"total_earnings_cents":500' "$RESPONSE_FILE" >/dev/null
node -e '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(body.products) || body.products.length < 2) process.exit(1);
if (body.products[0].title !== "Croissant") process.exit(1);
if (body.products[1].title !== "Muffin") process.exit(1);
if (!Array.isArray(body.orders) || body.orders.length !== 1) process.exit(1);
' "$RESPONSE_FILE"

echo "CODEVALID_TEST_ASSERTION_OK:happy_path_dashboard_success"

# Cleanup — handled by trap to remove seeded rows
