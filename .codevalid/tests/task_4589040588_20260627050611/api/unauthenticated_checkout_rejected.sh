#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-unauth-${CASE_SUFFIX}"
SELLER_EMAIL="seller-unauth-${CASE_SUFFIX}@example.com"
SELLER_ID="seller-unauth-${CASE_SUFFIX}"
PRODUCT_ID="prod-unauth-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/unauthenticated_checkout_rejected_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/unauthenticated_checkout_rejected_${CASE_SUFFIX}.status"
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
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Unauth Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES ('${PRODUCT_ID}','${SELLER_ID}','Unauth Widget ${CASE_SUFFIX}','Unauth checkout product','widgets',1000,5,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_ID}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "401" ]

echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_checkout_rejected"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}' OR email = '${SELLER_EMAIL}';" >/dev/null
