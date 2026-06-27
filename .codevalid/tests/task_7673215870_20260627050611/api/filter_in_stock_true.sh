#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-instock-${CASE_SUFFIX}"
SELLER_ID="seller-instock-${CASE_SUFFIX}"
PRODUCT_I_ID="prod-009-${CASE_SUFFIX}"
PRODUCT_J_ID="prod-010-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/filter_in_stock_true_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/filter_in_stock_true_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${PRODUCT_I_ID}','${PRODUCT_J_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT_I_ID}','${PRODUCT_J_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','instock-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','In Stock Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES
  ('${PRODUCT_I_ID}','${SELLER_ID}','Ink Pack ${CASE_SUFFIX}','Office item in stock','OFFICE',1200,10,TRUE,'ACTIVE',NOW() - INTERVAL '2 minutes'),
  ('${PRODUCT_J_ID}','${SELLER_ID}','Jumbo Paper ${CASE_SUFFIX}','Office item sold out','OFFICE',800,0,TRUE,'ACTIVE',NOW() - INTERVAL '1 minute');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?in_stock=true" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg match "$PRODUCT_I_ID" --arg other "$PRODUCT_J_ID" '
  type == "array" and
  (map(.id) | index($match)) != null and
  (map(.id) | index($other)) == null and
  all(.[]; .stockQty > 0)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:filter_in_stock_true"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${PRODUCT_I_ID}','${PRODUCT_J_ID}'); DELETE FROM products WHERE id IN ('${PRODUCT_I_ID}','${PRODUCT_J_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
