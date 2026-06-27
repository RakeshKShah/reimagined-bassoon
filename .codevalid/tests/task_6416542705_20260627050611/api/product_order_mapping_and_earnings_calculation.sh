#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-earnings-${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp-earnings-${CASE_SUFFIX}"
PRODUCT_ID_OLDER="prod-mouse-${CASE_SUFFIX}"
PRODUCT_ID_NEWER="prod-hub-${CASE_SUFFIX}"
BUYER_ID="buyer-earnings-${CASE_SUFFIX}"
ORDER_ID_ONE="ord-earnings-1-${CASE_SUFFIX}"
ORDER_ID_TWO="ord-earnings-2-${CASE_SUFFIX}"
ORDER_ITEM_ID_ONE="oi-earnings-1-${CASE_SUFFIX}"
ORDER_ITEM_ID_TWO="oi-earnings-2-${CASE_SUFFIX}"
SELLER_EMAIL="seller-earnings-${CASE_SUFFIX}@example.com"
BUYER_EMAIL="buyer-earnings-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/product_order_mapping_and_earnings_calculation_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/product_order_mapping_and_earnings_calculation_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE",sellerProfileId:process.argv[3]}, process.argv[4], {expiresIn:"7d"}));' "$USER_ID" "$SELLER_EMAIL" "$SELLER_PROFILE_ID" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id IN ('${ORDER_ITEM_ID_ONE}', '${ORDER_ITEM_ID_TWO}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id IN ('${ORDER_ID_ONE}', '${ORDER_ID_TWO}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PRODUCT_ID_OLDER}', '${PRODUCT_ID_NEWER}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}', '${BUYER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create active seller, two products, and two paid order items totaling 5000 cents
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${USER_ID}', '${SELLER_EMAIL}', 'seed-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio, created_at)
VALUES ('${SELLER_PROFILE_ID}', '${USER_ID}', 'Tech Gadgets', 'Cool tech', NOW());
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at)
VALUES
  ('${PRODUCT_ID_OLDER}', '${SELLER_PROFILE_ID}', 'Wireless Mouse', 'Ergonomic mouse', 'Electronics', 2500, 10, ARRAY['https://example.com/mouse.jpg'], 'ACTIVE', true, TIMESTAMPTZ '2024-02-01T10:00:00Z', NOW()),
  ('${PRODUCT_ID_NEWER}', '${SELLER_PROFILE_ID}', 'USB-C Hub', 'Multiport adapter', 'Electronics', 3000, 15, ARRAY['https://example.com/hub.jpg'], 'ACTIVE', true, TIMESTAMPTZ '2024-02-03T12:00:00Z', NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', 'seed-hash', 'BUYER', 'ACTIVE', NOW());
INSERT INTO orders (id, buyer_id, status, subtotal_cents, fee_cents, total_cents, created_at, updated_at)
VALUES
  ('${ORDER_ID_ONE}', '${BUYER_ID}', 'PAID', 2500, 0, 2500, TIMESTAMPTZ '2024-02-04T09:00:00Z', NOW()),
  ('${ORDER_ID_TWO}', '${BUYER_ID}', 'PAID', 6000, 0, 6000, TIMESTAMPTZ '2024-02-05T10:00:00Z', NOW());
INSERT INTO order_items (id, order_id, product_id, qty, unit_price_cents, seller_payout_cents, created_at)
VALUES
  ('${ORDER_ITEM_ID_ONE}', '${ORDER_ID_ONE}', '${PRODUCT_ID_OLDER}', 1, 2500, 2000, TIMESTAMPTZ '2024-02-04T09:00:00Z'),
  ('${ORDER_ITEM_ID_TWO}', '${ORDER_ID_TWO}', '${PRODUCT_ID_NEWER}', 2, 3000, 3000, TIMESTAMPTZ '2024-02-05T10:00:00Z');
SQL

# When — load seller dashboard
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — verify product sort order, order mapping, and total earnings
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"store_name":"Tech Gadgets"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Cool tech"' "$RESPONSE_FILE" >/dev/null
grep -F '"total_earnings_cents":5000' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"${ORDER_ITEM_ID_ONE}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"${ORDER_ITEM_ID_TWO}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"product_title":"Wireless Mouse"' "$RESPONSE_FILE" >/dev/null
grep -F '"product_title":"USB-C Hub"' "$RESPONSE_FILE" >/dev/null
node -e '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(body.products) || body.products.length < 2) process.exit(1);
if (body.products[0].title !== "USB-C Hub") process.exit(1);
if (body.products[1].title !== "Wireless Mouse") process.exit(1);
if (!Array.isArray(body.orders) || body.orders.length !== 2) process.exit(1);
if (body.total_earnings_cents !== 5000) process.exit(1);
' "$RESPONSE_FILE"

echo "CODEVALID_TEST_ASSERTION_OK:product_order_mapping_and_earnings_calculation"

# Cleanup — handled by trap to remove seeded rows
