#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
AUTH_BUYER_EMAIL="buyer-a-${CASE_SUFFIX}@example.com"
OWNER_BUYER_EMAIL="buyer-b-${CASE_SUFFIX}@example.com"
PASSWORD="BuyerPass789!"
PRODUCT_ID="prod-hij-${CASE_SUFFIX}"
ORDER_ID="order-400-${CASE_SUFFIX}"
ORDER_ITEM_ID="item-33-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/reject_review_for_other_buyer_item_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/reject_review_for_other_buyer_item_${CASE_SUFFIX}.status"
AUTH_FILE="/tmp/reject_review_for_other_buyer_item_auth_${CASE_SUFFIX}.json"
OWNER_FILE="/tmp/reject_review_for_other_buyer_item_owner_${CASE_SUFFIX}.json"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$AUTH_FILE" "$OWNER_FILE"; }
trap cleanup_files EXIT

# Given
curl -sS -o "$AUTH_FILE" \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${AUTH_BUYER_EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}"
AUTH_TOKEN="$(jq -r '.token' "$AUTH_FILE")"
AUTH_BUYER_ID="$(jq -r '.user.id' "$AUTH_FILE")"
[ -n "$AUTH_TOKEN" ]
[ "$AUTH_TOKEN" != "null" ]
[ -n "$AUTH_BUYER_ID" ]
[ "$AUTH_BUYER_ID" != "null" ]

curl -sS -o "$OWNER_FILE" \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${OWNER_BUYER_EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}"
OWNER_BUYER_ID="$(jq -r '.user.id' "$OWNER_FILE")"
[ -n "$OWNER_BUYER_ID" ]
[ "$OWNER_BUYER_ID" != "null" ]
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Store ${CASE_SUFFIX}', 'Bio ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Product ${CASE_SUFFIX}', 'Owned by another buyer', 'general', 1899, 5, '[]'::jsonb, 'ACTIVE', true);
INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents)
VALUES ('${ORDER_ID}', '${OWNER_BUYER_ID}', 'DELIVERED', 1899, 189);
INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 1899, 1710);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/reviews" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  --data "{\"order_item_id\":\"${ORDER_ITEM_ID}\",\"rating\":2,\"body\":\"Not my order\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
jq -e '.error == "Order item not found"' "$RESPONSE_FILE" >/dev/null
COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';")"
[ "$COUNT" = "0" ]

echo "CODEVALID_TEST_ASSERTION_OK:reject_review_for_other_buyer_item"

# Cleanup
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${AUTH_BUYER_ID}', '${OWNER_BUYER_ID}');
SQL
