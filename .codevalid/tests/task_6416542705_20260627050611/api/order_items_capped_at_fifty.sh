#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-cap-${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp-cap-${CASE_SUFFIX}"
PRODUCT_ID="prod-cap-${CASE_SUFFIX}"
BUYER_ID="buyer-cap-${CASE_SUFFIX}"
SELLER_EMAIL="seller-cap-${CASE_SUFFIX}@example.com"
BUYER_EMAIL="buyer-cap-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/order_items_capped_at_fifty_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/order_items_capped_at_fifty_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE",sellerProfileId:process.argv[3]}, process.argv[4], {expiresIn:"7d"}));' "$USER_ID" "$SELLER_EMAIL" "$SELLER_PROFILE_ID" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id LIKE 'oi-cap-%-${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id LIKE 'ord-cap-%-${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}', '${BUYER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create active seller and 55 recent order items for one product
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${USER_ID}', '${SELLER_EMAIL}', 'seed-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio, created_at)
VALUES ('${SELLER_PROFILE_ID}', '${USER_ID}', 'Volume Store', 'Handles many orders', NOW());
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Bulk Item', 'High volume listing', 'General', 999, 500, ARRAY['https://example.com/bulk.jpg'], 'ACTIVE', true, NOW(), NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', 'seed-hash', 'BUYER', 'ACTIVE', NOW());
SQL
i=1
while [ "$i" -le 55 ]; do
  ORDER_ID="ord-cap-${i}-${CASE_SUFFIX}"
  ORDER_ITEM_ID="oi-cap-${i}-${CASE_SUFFIX}"
  CREATED_AT="$(node -e 'const i=Number(process.argv[1]); const d=new Date(Date.UTC(2024,0,1,0,0,i)); process.stdout.write(d.toISOString());' "$i")"
  psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO orders (id, buyer_id, status, subtotal_cents, fee_cents, total_cents, created_at, updated_at)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'PAID', 999, 0, 999, TIMESTAMPTZ '${CREATED_AT}', NOW());
INSERT INTO order_items (id, order_id, product_id, qty, unit_price_cents, seller_payout_cents, created_at)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 999, 700, TIMESTAMPTZ '${CREATED_AT}');
SQL
  i=$((i + 1))
done

# When — load seller dashboard
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — verify only the 50 most recent order items are returned in descending order
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
node -e '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(body.orders)) process.exit(1);
if (body.orders.length !== 50) process.exit(1);
for (let i = 1; i < body.orders.length; i++) {
  const prev = new Date(body.orders[i - 1].created_at).getTime();
  const curr = new Date(body.orders[i].created_at).getTime();
  if (prev < curr) process.exit(1);
}
const ids = new Set(body.orders.map((o) => o.id));
if (!ids.has(`oi-cap-55-${process.argv[2]}`)) process.exit(1);
if (!ids.has(`oi-cap-6-${process.argv[2]}`)) process.exit(1);
if (ids.has(`oi-cap-5-${process.argv[2]}`)) process.exit(1);
if (ids.has(`oi-cap-1-${process.argv[2]}`)) process.exit(1);
' "$RESPONSE_FILE" "$CASE_SUFFIX"

echo "CODEVALID_TEST_ASSERTION_OK:order_items_capped_at_fifty"

# Cleanup — handled by trap to remove seeded rows
