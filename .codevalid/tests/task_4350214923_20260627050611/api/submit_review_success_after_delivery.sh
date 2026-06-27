#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer-42-${CASE_SUFFIX}@example.com"
PASSWORD="BuyerPass789!"
PRODUCT_ID="prod-abc-${CASE_SUFFIX}"
ORDER_ID="order-100-${CASE_SUFFIX}"
ORDER_ITEM_ID="item-7-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
REVIEW_BODY='Great product, fast delivery!'
RESPONSE_FILE="/tmp/submit_review_success_after_delivery_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/submit_review_success_after_delivery_${CASE_SUFFIX}.status"
BUYER_FILE="/tmp/submit_review_success_after_delivery_buyer_${CASE_SUFFIX}.json"
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
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Product ${CASE_SUFFIX}', 'Reviewable product', 'general', 1999, 5, '[]'::jsonb, 'ACTIVE', true);
INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'DELIVERED', 1999, 199);
INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 1999, 1800);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/reviews" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"order_item_id\":\"${ORDER_ITEM_ID}\",\"rating\":5,\"body\":\"${REVIEW_BODY}\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
jq -e --arg order_item_id "$ORDER_ITEM_ID" --arg product_id "$PRODUCT_ID" --arg buyer_id "$BUYER_ID" --arg body "$REVIEW_BODY" '
  .orderItemId == $order_item_id and
  .productId == $product_id and
  .buyerId == $buyer_id and
  .rating == 5 and
  .body == $body and
  (.id | type == "string" and length > 0)
' "$RESPONSE_FILE" >/dev/null
psql "$DATABASE_URL" -t -A -c "SELECT body FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}' AND buyer_id = '${BUYER_ID}' AND product_id = '${PRODUCT_ID}' AND rating = 5;" | grep -Fx "$REVIEW_BODY" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:submit_review_success_after_delivery"

# Cleanup
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER_ID}');
SQL
