#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_A_ID="prod-A-${CASE_SUFFIX}"
PRODUCT_B_ID="prod-B-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
BUYER1_ID="buyer-1-${CASE_SUFFIX}"
BUYER2_ID="buyer-2-${CASE_SUFFIX}"
BUYER3_ID="buyer-3-${CASE_SUFFIX}"
BUYER4_ID="buyer-4-${CASE_SUFFIX}"
BUYER5_ID="buyer-5-${CASE_SUFFIX}"
ORDER_A1_ID="order-a1-${CASE_SUFFIX}"
ORDER_A2_ID="order-a2-${CASE_SUFFIX}"
ORDER_B1_ID="order-b1-${CASE_SUFFIX}"
ORDER_B2_ID="order-b2-${CASE_SUFFIX}"
ORDER_B3_ID="order-b3-${CASE_SUFFIX}"
ITEM_A1_ID="item-a1-${CASE_SUFFIX}"
ITEM_A2_ID="item-a2-${CASE_SUFFIX}"
ITEM_B1_ID="item-b1-${CASE_SUFFIX}"
ITEM_B2_ID="item-b2-${CASE_SUFFIX}"
ITEM_B3_ID="item-b3-${CASE_SUFFIX}"
REV_A1_ID="rev-A1-${CASE_SUFFIX}"
REV_A2_ID="rev-A2-${CASE_SUFFIX}"
REV_B1_ID="rev-B1-${CASE_SUFFIX}"
REV_B2_ID="rev-B2-${CASE_SUFFIX}"
REV_B3_ID="rev-B3-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_reviews_multiple_product_isolation_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_reviews_multiple_product_isolation_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT
export REV_A1_ID REV_A2_ID REV_B1_ID REV_B2_ID REV_B3_ID

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW()),
  ('${BUYER1_ID}', 'buyer1-${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW()),
  ('${BUYER2_ID}', 'buyer2-${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW()),
  ('${BUYER3_ID}', 'buyer3-${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW()),
  ('${BUYER4_ID}', 'buyer4-${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW()),
  ('${BUYER5_ID}', 'buyer5-${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW());

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Isolation Store ${CASE_SUFFIX}', '');

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES
  ('${PRODUCT_A_ID}', '${SELLER_PROFILE_ID}', 'Product A', 'Isolation A', 'general', 1000, 10, '[]', 'ACTIVE', true, NOW()),
  ('${PRODUCT_B_ID}', '${SELLER_PROFILE_ID}', 'Product B', 'Isolation B', 'general', 2000, 10, '[]', 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at) VALUES
  ('${ORDER_A1_ID}', '${BUYER1_ID}', 'DELIVERED', 1000, 100, NOW()),
  ('${ORDER_A2_ID}', '${BUYER2_ID}', 'DELIVERED', 1000, 100, NOW()),
  ('${ORDER_B1_ID}', '${BUYER3_ID}', 'DELIVERED', 2000, 200, NOW()),
  ('${ORDER_B2_ID}', '${BUYER4_ID}', 'DELIVERED', 2000, 200, NOW()),
  ('${ORDER_B3_ID}', '${BUYER5_ID}', 'DELIVERED', 2000, 200, NOW());

INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents) VALUES
  ('${ITEM_A1_ID}', '${ORDER_A1_ID}', '${PRODUCT_A_ID}', '${SELLER_PROFILE_ID}', 1, 1000, 900),
  ('${ITEM_A2_ID}', '${ORDER_A2_ID}', '${PRODUCT_A_ID}', '${SELLER_PROFILE_ID}', 1, 1000, 900),
  ('${ITEM_B1_ID}', '${ORDER_B1_ID}', '${PRODUCT_B_ID}', '${SELLER_PROFILE_ID}', 1, 2000, 1800),
  ('${ITEM_B2_ID}', '${ORDER_B2_ID}', '${PRODUCT_B_ID}', '${SELLER_PROFILE_ID}', 1, 2000, 1800),
  ('${ITEM_B3_ID}', '${ORDER_B3_ID}', '${PRODUCT_B_ID}', '${SELLER_PROFILE_ID}', 1, 2000, 1800);

INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at) VALUES
  ('${REV_A1_ID}', '${ITEM_A1_ID}', '${PRODUCT_A_ID}', '${BUYER1_ID}', 4, 'A1', '2024-01-01T10:00:00Z'),
  ('${REV_A2_ID}', '${ITEM_A2_ID}', '${PRODUCT_A_ID}', '${BUYER2_ID}', 5, 'A2', '2024-01-02T10:00:00Z'),
  ('${REV_B1_ID}', '${ITEM_B1_ID}', '${PRODUCT_B_ID}', '${BUYER3_ID}', 2, 'B1', '2024-01-03T10:00:00Z'),
  ('${REV_B2_ID}', '${ITEM_B2_ID}', '${PRODUCT_B_ID}', '${BUYER4_ID}', 3, 'B2', '2024-01-04T10:00:00Z'),
  ('${REV_B3_ID}', '${ITEM_B3_ID}', '${PRODUCT_B_ID}', '${BUYER5_ID}', 5, 'B3', '2024-01-05T10:00:00Z');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products/${PRODUCT_B_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 3' "$RESPONSE_FILE" >/dev/null
jq -e 'map(.id) == [env.REV_B3_ID, env.REV_B2_ID, env.REV_B1_ID]' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == env.REV_A1_ID or .id == env.REV_A2_ID)) | length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_reviews_multiple_product_isolation"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE id IN ('${REV_A1_ID}', '${REV_A2_ID}', '${REV_B1_ID}', '${REV_B2_ID}', '${REV_B3_ID}');
DELETE FROM order_items WHERE id IN ('${ITEM_A1_ID}', '${ITEM_A2_ID}', '${ITEM_B1_ID}', '${ITEM_B2_ID}', '${ITEM_B3_ID}');
DELETE FROM orders WHERE id IN ('${ORDER_A1_ID}', '${ORDER_A2_ID}', '${ORDER_B1_ID}', '${ORDER_B2_ID}', '${ORDER_B3_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT_A_ID}', '${PRODUCT_B_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER1_ID}', '${BUYER2_ID}', '${BUYER3_ID}', '${BUYER4_ID}', '${BUYER5_ID}');
SQL
