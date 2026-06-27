#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-public-${CASE_SUFFIX}"
SELLER_ID="seller-public-${CASE_SUFFIX}"
PRODUCT_O_ID="prod-015-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/unauthenticated_browse_succeeds_optional_auth_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/unauthenticated_browse_succeeds_optional_auth_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id = '${PRODUCT_O_ID}';
DELETE FROM products WHERE id = '${PRODUCT_O_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','public-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Public Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES ('${PRODUCT_O_ID}','${SELLER_ID}','Omega Watch ${CASE_SUFFIX}','Publicly browseable product','WATCHES',12900,1,TRUE,'ACTIVE',NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg id "$PRODUCT_O_ID" 'type == "array" and (map(.id) | index($id)) != null' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_browse_succeeds_optional_auth"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id = '${PRODUCT_O_ID}'; DELETE FROM products WHERE id = '${PRODUCT_O_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
