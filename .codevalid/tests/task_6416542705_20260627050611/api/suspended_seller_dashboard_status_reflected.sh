#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-suspended-${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp-suspended-${CASE_SUFFIX}"
PRODUCT_ID="prod-suspended-${CASE_SUFFIX}"
ORDER_ID="ord-suspended-${CASE_SUFFIX}"
ORDER_ITEM_ID="oi-suspended-${CASE_SUFFIX}"
BUYER_ID="buyer-suspended-${CASE_SUFFIX}"
SELLER_EMAIL="seller-suspended-${CASE_SUFFIX}@example.com"
BUYER_EMAIL="buyer-suspended-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/suspended_seller_dashboard_status_reflected_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/suspended_seller_dashboard_status_reflected_${CASE_SUFFIX}.status"
TOKEN="$(node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"SUSPENDED",sellerProfileId:process.argv[3]}, process.argv[4], {expiresIn:"7d"}));' "$USER_ID" "$SELLER_EMAIL" "$SELLER_PROFILE_ID" "$JWT_SECRET")"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id = '${ORDER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}', '${BUYER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create suspended seller with profile, product, buyer, and one order item
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${USER_ID}', '${SELLER_EMAIL}', 'seed-hash', 'SELLER', 'SUSPENDED', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio, created_at)
VALUES ('${SELLER_PROFILE_ID}', '${USER_ID}', 'Suspended Store', 'Under review', NOW());
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at, updated_at)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Review Item', 'Suspended seller item', 'General', 1200, 4, '["https://example.com/review.jpg"]'::jsonb, 'ACTIVE', true, NOW(), NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', 'seed-hash', 'BUYER', 'ACTIVE', NOW());
INSERT INTO orders (id, buyer_id, status, subtotal_cents, fee_cents, total_cents, created_at, updated_at)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'PAID', 1200, 0, 1200, NOW(), NOW());
INSERT INTO order_items (id, order_id, product_id, qty, unit_price_cents, seller_payout_cents, created_at)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 1200, 900, NOW());
SQL

# When — suspended seller loads own dashboard
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" \
  -H "Authorization: Bearer $TOKEN" > "$STATUS_FILE"

# Then — verify suspended status and own listing/order visibility are reflected
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"status":"SUSPENDED"' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Suspended Store"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Under review"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"${PRODUCT_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"${ORDER_ITEM_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"buyer_email":"'"${BUYER_EMAIL}"'"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_dashboard_status_reflected"

# Cleanup — handled by trap to remove seeded rows
