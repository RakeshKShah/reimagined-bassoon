#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-role-${CASE_SUFFIX}"
SELLER_EMAIL="seller-role-${CASE_SUFFIX}@example.com"
SELLER_ID="seller-role-${CASE_SUFFIX}"
PRODUCT_ID="prod-role-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/unauthorized_non_buyer_role_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/unauthorized_non_buyer_role_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id = '${PRODUCT_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}' OR email = '${SELLER_EMAIL}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','${SELLER_EMAIL}','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Role Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES ('${PRODUCT_ID}','${SELLER_ID}','Role Widget ${CASE_SUFFIX}','Role restricted checkout product','widgets',1000,5,TRUE,'ACTIVE');
SQL
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'SELLER', status: 'ACTIVE'}, process.argv[3]));" "$SELLER_USER_ID" "$SELLER_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_ID}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
ORDER_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM orders WHERE buyer_id = '${SELLER_USER_ID}';")"
[ "$ORDER_COUNT" = "0" ]

echo "CODEVALID_TEST_ASSERTION_OK:unauthorized_non_buyer_role"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}' OR email = '${SELLER_EMAIL}';" >/dev/null
