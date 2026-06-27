#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer-55-${CASE_SUFFIX}@example.com"
PASSWORD="BuyerPass789!"
PRODUCT_ID="prod-def-${CASE_SUFFIX}"
ORDER_ID="order-300-${CASE_SUFFIX}"
ORDER_ITEM_ID="item-22-${CASE_SUFFIX}"
REVIEW_ID="review-88-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/prevent_duplicate_review_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/prevent_duplicate_review_${CASE_SUFFIX}.status"
BUYER_FILE="/tmp/prevent_duplicate_review_buyer_${CASE_SUFFIX}.json"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$BUYER_FILE"; }
trap cleanup_files EXIT

# Given
curl -sS -o "$BUYER_FILE" \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}"
TOKEN="$(jq -r '.token' "$BUYER_FILE")"
BUYER_ID="$(jq -r '.user.id' "$BUYER_FILE")"
[ -n "$TOKEN" ]
[ "$TOKEN" != "null" ]
[ -n "$BUYER_ID" ]
[ "$BUYER_ID" != "null" ]
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Store ${CASE_SUFFIX}', 'Bio ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Product ${CASE_SUFFIX}', 'Already reviewed product', 'general', 2599, 5, '[]'::jsonb, 'ACTIVE', true);
INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'DELIVERED', 2599, 259);
INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 2599, 2340);
INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body)
VALUES ('${REVIEW_ID}', '${ORDER_ITEM_ID}', '${PRODUCT_ID}', '${BUYER_ID}', 5, 'Original review');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/reviews" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"order_item_id\":\"${ORDER_ITEM_ID}\",\"rating\":3,\"body\":\"Updating my review\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
jq -e '.error == "Already reviewed"' "$RESPONSE_FILE" >/dev/null
COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';")"
[ "$COUNT" = "1" ]
psql "$DATABASE_URL" -t -A -c "SELECT body FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';" | grep -Fx 'Original review' >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:prevent_duplicate_review"

# Cleanup
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER_ID}');
SQL
