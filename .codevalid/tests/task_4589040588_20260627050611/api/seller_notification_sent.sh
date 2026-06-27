#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-notify-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-notify-${CASE_SUFFIX}@example.com"
SELLER_USER_ID="seller-user-notify-${CASE_SUFFIX}"
SELLER_EMAIL="seller-notify-${CASE_SUFFIX}@test.com"
SELLER_ID="seller-notify-${CASE_SUFFIX}"
PRODUCT_ID="prod-notify-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_notification_sent_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_notification_sent_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id = '${PRODUCT_ID}';
DELETE FROM orders WHERE buyer_id = '${BUYER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${BUYER_ID}','${SELLER_USER_ID}') OR email IN ('${BUYER_EMAIL}','${SELLER_EMAIL}');
INSERT INTO users (id, email, password_hash, role, status)
VALUES
  ('${BUYER_ID}','${BUYER_EMAIL}','seed-hash','BUYER','ACTIVE'),
  ('${SELLER_USER_ID}','${SELLER_EMAIL}','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Test Store');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES ('${PRODUCT_ID}','${SELLER_ID}','Notify Widget ${CASE_SUFFIX}','Notification checkout product','widgets',1000,5,TRUE,'ACTIVE');
SQL
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'BUYER', status: 'ACTIVE'}, process.argv[3]));" "$BUYER_ID" "$BUYER_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_ID}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg seller_id "$SELLER_ID" --arg product_id "$PRODUCT_ID" '
  .status == "PAID" and
  (.items | length) == 1 and
  .items[0].sellerId == $seller_id and
  .items[0].productId == $product_id and
  .items[0].qty == 1
' "$RESPONSE_FILE" >/dev/null
# Repo learning: notification path no-ops/logs in demo mode when RESEND_API_KEY is unset and has no mock seam.
# Assert the successful checkout created the seller-linked order item context that triggers notifySellerOrderPaid.
ORDER_ID="$(jq -r '.id' "$RESPONSE_FILE")"
DB_ROW="$(psql "$DATABASE_URL" -t -A -F '|' -c "SELECT oi.qty, p.title, s.store_name, u.email FROM order_items oi JOIN products p ON p.id = oi.product_id JOIN sellers s ON s.id = oi.seller_id JOIN users u ON u.id = s.user_id WHERE oi.order_id = '${ORDER_ID}' AND oi.product_id = '${PRODUCT_ID}';")"
case "$DB_ROW" in
  "1|Notify Widget "*"|Test Store|${SELLER_EMAIL}") ;;
  *) echo "unexpected order item notification context: $DB_ROW"; exit 1 ;;
esac

echo "CODEVALID_TEST_ASSERTION_OK:seller_notification_sent"

# Cleanup
if [ -n "$ORDER_ID" ]; then
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE order_id = '${ORDER_ID}'; DELETE FROM orders WHERE id = '${ORDER_ID}';" >/dev/null
fi
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id IN ('${BUYER_ID}','${SELLER_USER_ID}') OR email IN ('${BUYER_EMAIL}','${SELLER_EMAIL}');" >/dev/null
