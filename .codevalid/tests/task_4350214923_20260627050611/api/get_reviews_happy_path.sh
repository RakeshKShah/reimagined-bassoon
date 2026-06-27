#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-789-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
BUYER1_ID="buyer-1-${CASE_SUFFIX}"
BUYER2_ID="buyer-2-${CASE_SUFFIX}"
BUYER3_ID="buyer-3-${CASE_SUFFIX}"
ORDER1_ID="order-1-${CASE_SUFFIX}"
ORDER2_ID="order-2-${CASE_SUFFIX}"
ORDER3_ID="order-3-${CASE_SUFFIX}"
ORDER_ITEM1_ID="order-item-1-${CASE_SUFFIX}"
ORDER_ITEM2_ID="order-item-2-${CASE_SUFFIX}"
ORDER_ITEM3_ID="order-item-3-${CASE_SUFFIX}"
REVIEW1_ID="rev-001-${CASE_SUFFIX}"
REVIEW2_ID="rev-002-${CASE_SUFFIX}"
REVIEW3_ID="rev-003-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_reviews_happy_path_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_reviews_happy_path_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT
export REVIEW1_ID REVIEW2_ID REVIEW3_ID

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW()),
  ('${BUYER1_ID}', 'alice@example.com', 'hash', 'BUYER', 'ACTIVE', NOW()),
  ('${BUYER2_ID}', 'bob@example.com', 'hash', 'BUYER', 'ACTIVE', NOW()),
  ('${BUYER3_ID}', 'carol@example.com', 'hash', 'BUYER', 'ACTIVE', NOW());

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Review Store ${CASE_SUFFIX}', '');

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Reviewed Product', 'Product for review listing', 'general', 1999, 10, '[]', 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at) VALUES
  ('${ORDER1_ID}', '${BUYER1_ID}', 'DELIVERED', 1999, 200, NOW()),
  ('${ORDER2_ID}', '${BUYER2_ID}', 'DELIVERED', 1999, 200, NOW()),
  ('${ORDER3_ID}', '${BUYER3_ID}', 'DELIVERED', 1999, 200, NOW());

INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents) VALUES
  ('${ORDER_ITEM1_ID}', '${ORDER1_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 1999, 1799),
  ('${ORDER_ITEM2_ID}', '${ORDER2_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 1999, 1799),
  ('${ORDER_ITEM3_ID}', '${ORDER3_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 1999, 1799);

INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at) VALUES
  ('${REVIEW1_ID}', '${ORDER_ITEM1_ID}', '${PRODUCT_ID}', '${BUYER1_ID}', 5, 'Excellent quality!', '2024-01-15T10:00:00Z'),
  ('${REVIEW2_ID}', '${ORDER_ITEM2_ID}', '${PRODUCT_ID}', '${BUYER2_ID}', 3, 'Average product', '2024-01-20T14:30:00Z'),
  ('${REVIEW3_ID}', '${ORDER_ITEM3_ID}', '${PRODUCT_ID}', '${BUYER3_ID}', 4, 'Good value for money', '2024-01-18T09:15:00Z');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 3' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == env.REVIEW2_ID and .[0].rating == 3 and .[0].body == "Average product" and .[0].buyer_email == "bo***@example.com"' "$RESPONSE_FILE" >/dev/null
jq -e '.[1].id == env.REVIEW3_ID and .[1].rating == 4 and .[1].body == "Good value for money" and .[1].buyer_email == "ca***@example.com"' "$RESPONSE_FILE" >/dev/null
jq -e '.[2].id == env.REVIEW1_ID and .[2].rating == 5 and .[2].body == "Excellent quality!" and .[2].buyer_email == "al***@example.com"' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].created_at == "2024-01-20T14:30:00.000Z" and .[1].created_at == "2024-01-18T09:15:00.000Z" and .[2].created_at == "2024-01-15T10:00:00.000Z"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_reviews_happy_path"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE id IN ('${REVIEW1_ID}', '${REVIEW2_ID}', '${REVIEW3_ID}');
DELETE FROM order_items WHERE id IN ('${ORDER_ITEM1_ID}', '${ORDER_ITEM2_ID}', '${ORDER_ITEM3_ID}');
DELETE FROM orders WHERE id IN ('${ORDER1_ID}', '${ORDER2_ID}', '${ORDER3_ID}');
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER1_ID}', '${BUYER2_ID}', '${BUYER3_ID}');
SQL
