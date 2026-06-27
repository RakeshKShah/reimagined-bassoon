#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="user-buyer-5-${CASE_SUFFIX}"
BUYER_EMAIL="checkout-nonexistent-${CASE_SUFFIX}@example.com"
PRODUCT_ID="prod-nonexistent-999-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/checkout_nonexistent_product_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_nonexistent_product_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM orders WHERE buyer_id = '${BUYER_ID}';
DELETE FROM users WHERE id = '${BUYER_ID}' OR email = '${BUYER_EMAIL}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${BUYER_ID}','${BUYER_EMAIL}','seed-hash','BUYER','ACTIVE');
DELETE FROM products WHERE id = '${PRODUCT_ID}';
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
[ "$STATUS" = "400" ]
jq -e --arg msg "Product ${PRODUCT_ID} unavailable" '.error == $msg' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:checkout_nonexistent_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM orders WHERE buyer_id = '${BUYER_ID}'; DELETE FROM users WHERE id = '${BUYER_ID}' OR email = '${BUYER_EMAIL}';" >/dev/null
