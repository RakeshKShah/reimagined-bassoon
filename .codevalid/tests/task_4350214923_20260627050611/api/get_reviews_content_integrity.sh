#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-456-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
BUYER_ID="buyer-${CASE_SUFFIX}"
ORDER_ID="order-${CASE_SUFFIX}"
ORDER_ITEM_ID="order-item-${CASE_SUFFIX}"
REVIEW_ID="rev-test-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_reviews_content_integrity_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_reviews_content_integrity_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT
export REVIEW_ID

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW()),
  ('${BUYER_ID}', 'test@example.com', 'hash', 'BUYER', 'ACTIVE', NOW());

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Integrity Store ${CASE_SUFFIX}', '');

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Integrity Product', 'Product for integrity test', 'general', 1800, 4, '[]', 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'DELIVERED', 1800, 180, NOW());

INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 1800, 1620);

INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at)
VALUES ('${REVIEW_ID}', '${ORDER_ITEM_ID}', '${PRODUCT_ID}', '${BUYER_ID}', 2, 'This is my honest review with special chars: !@#$%', '2024-02-01T12:00:00Z');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 1' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == env.REVIEW_ID and .[0].rating == 2 and .[0].body == "This is my honest review with special chars: !@#$%" and .[0].buyer_email == "te***@example.com"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_reviews_content_integrity"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE id = '${REVIEW_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER_ID}');
SQL
