#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-order-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
BUYER_A_ID="buyer-a-${CASE_SUFFIX}"
BUYER_B_ID="buyer-b-${CASE_SUFFIX}"
BUYER_C_ID="buyer-c-${CASE_SUFFIX}"
ORDER_A_ID="order-a-${CASE_SUFFIX}"
ORDER_B_ID="order-b-${CASE_SUFFIX}"
ORDER_C_ID="order-c-${CASE_SUFFIX}"
ITEM_A_ID="item-a-${CASE_SUFFIX}"
ITEM_B_ID="item-b-${CASE_SUFFIX}"
ITEM_C_ID="item-c-${CASE_SUFFIX}"
REVIEW_A_ID="review-a-${CASE_SUFFIX}"
REVIEW_B_ID="review-b-${CASE_SUFFIX}"
REVIEW_C_ID="review-c-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_reviews_ordered_by_date_descending_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_reviews_ordered_by_date_descending_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT
export REVIEW_A_ID REVIEW_B_ID REVIEW_C_ID

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW()),
  ('${BUYER_A_ID}', 'a-${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW()),
  ('${BUYER_B_ID}', 'b-${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW()),
  ('${BUYER_C_ID}', 'c-${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW());

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Ordering Store ${CASE_SUFFIX}', '');

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Ordering Product', 'Product for ordering test', 'general', 3000, 6, '[]', 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at) VALUES
  ('${ORDER_A_ID}', '${BUYER_A_ID}', 'DELIVERED', 3000, 300, NOW()),
  ('${ORDER_B_ID}', '${BUYER_B_ID}', 'DELIVERED', 3000, 300, NOW()),
  ('${ORDER_C_ID}', '${BUYER_C_ID}', 'DELIVERED', 3000, 300, NOW());

INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents) VALUES
  ('${ITEM_A_ID}', '${ORDER_A_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 3000, 2700),
  ('${ITEM_B_ID}', '${ORDER_B_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 3000, 2700),
  ('${ITEM_C_ID}', '${ORDER_C_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 3000, 2700);

INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at) VALUES
  ('${REVIEW_A_ID}', '${ITEM_A_ID}', '${PRODUCT_ID}', '${BUYER_A_ID}', 2, 'Review A', '2023-12-01T08:00:00Z'),
  ('${REVIEW_B_ID}', '${ITEM_B_ID}', '${PRODUCT_ID}', '${BUYER_B_ID}', 5, 'Review B', '2024-01-10T12:00:00Z'),
  ('${REVIEW_C_ID}', '${ITEM_C_ID}', '${PRODUCT_ID}', '${BUYER_C_ID}', 4, 'Review C', '2024-01-05T16:00:00Z');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 3' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == env.REVIEW_B_ID and .[1].id == env.REVIEW_C_ID and .[2].id == env.REVIEW_A_ID' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].created_at == "2024-01-10T12:00:00.000Z" and .[1].created_at == "2024-01-05T16:00:00.000Z" and .[2].created_at == "2023-12-01T08:00:00.000Z"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_reviews_ordered_by_date_descending"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE id IN ('${REVIEW_A_ID}', '${REVIEW_B_ID}', '${REVIEW_C_ID}');
DELETE FROM order_items WHERE id IN ('${ITEM_A_ID}', '${ITEM_B_ID}', '${ITEM_C_ID}');
DELETE FROM orders WHERE id IN ('${ORDER_A_ID}', '${ORDER_B_ID}', '${ORDER_C_ID}');
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER_A_ID}', '${BUYER_B_ID}', '${BUYER_C_ID}');
SQL
