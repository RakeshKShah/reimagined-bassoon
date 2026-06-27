#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer-display-${CASE_SUFFIX}@example.com"
VIEWER_EMAIL="future-buyer-${CASE_SUFFIX}@example.com"
PASSWORD="BuyerPass789!"
PRODUCT_ID="prod-display-${CASE_SUFFIX}"
ORDER_ID="order-display-${CASE_SUFFIX}"
ORDER_ITEM_ID="item-display-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
REVIEW_BODY='Displayed review content must match exactly.'
RESPONSE_FILE="/tmp/handle_unexpected_database_error_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/handle_unexpected_database_error_${CASE_SUFFIX}.status"
BUYER_FILE="/tmp/review_display_content_integrity_buyer_${CASE_SUFFIX}.json"
VIEWER_FILE="/tmp/review_display_content_integrity_viewer_${CASE_SUFFIX}.json"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$BUYER_FILE" "$VIEWER_FILE"; }
trap cleanup_files EXIT

# Given
curl -sS -o "$BUYER_FILE" \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}"
BUYER_TOKEN="$(jq -r '.token' "$BUYER_FILE")"
BUYER_ID="$(jq -r '.user.id' "$BUYER_FILE")"
[ -n "$BUYER_TOKEN" ]
[ "$BUYER_TOKEN" != "null" ]
[ -n "$BUYER_ID" ]
[ "$BUYER_ID" != "null" ]

curl -sS -o "$VIEWER_FILE" \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${VIEWER_EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}"
VIEWER_ID="$(jq -r '.user.id' "$VIEWER_FILE")"
[ -n "$VIEWER_ID" ]
[ "$VIEWER_ID" != "null" ]
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', 'seed-hash', 'SELLER', 'ACTIVE');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Store ${CASE_SUFFIX}', 'Bio ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Product ${CASE_SUFFIX}', 'Display review product', 'general', 2499, 5, '[]'::jsonb, 'ACTIVE', true);
INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'DELIVERED', 2499, 249);
INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 2499, 2250);
SQL
curl -sS -o /dev/null -w '%{http_code}' \
  -X POST "$BASE_URL/reviews" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${BUYER_TOKEN}" \
  --data "{\"order_item_id\":\"${ORDER_ITEM_ID}\",\"rating\":5,\"body\":\"${REVIEW_BODY}\"}" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg body "$REVIEW_BODY" '
  type == "array" and
  length >= 1 and
  .[0].body == $body and
  .[0].rating == 5 and
  (.[0].buyer_email | type == "string" and contains("***@"))
' "$RESPONSE_FILE" >/dev/null
psql "$DATABASE_URL" -t -A -c "SELECT body FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';" | grep -Fx "$REVIEW_BODY" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:handle_unexpected_database_error"

# Cleanup
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}', '${BUYER_ID}', '${VIEWER_ID}');
SQL
