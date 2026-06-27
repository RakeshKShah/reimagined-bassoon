#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-removed-${CASE_SUFFIX}"
SELLER_ID="seller-removed-${CASE_SUFFIX}"
PRODUCT_P_ID="prod-016-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/excluded_products_with_removed_status_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/excluded_products_with_removed_status_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id = '${PRODUCT_P_ID}';
DELETE FROM products WHERE id = '${PRODUCT_P_ID}';
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','removed-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Removed Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES ('${PRODUCT_P_ID}','${SELLER_ID}','Phantom Item ${CASE_SUFFIX}','Removed catalog item','MISC',1000,0,TRUE,'REMOVED',NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg id "$PRODUCT_P_ID" 'type == "array" and (map(.id) | index($id)) == null' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:excluded_products_with_removed_status"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id = '${PRODUCT_P_ID}'; DELETE FROM products WHERE id = '${PRODUCT_P_ID}'; DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
