#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-category-${CASE_SUFFIX}"
SELLER_ID="seller-category-${CASE_SUFFIX}"
PRODUCT_E_ID="prod-005-${CASE_SUFFIX}"
PRODUCT_F_ID="prod-006-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/search_by_category_matching_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/search_by_category_matching_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${PRODUCT_E_ID}','${PRODUCT_F_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT_E_ID}','${PRODUCT_F_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','category-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Category Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES
  ('${PRODUCT_E_ID}','${SELLER_ID}','Echo Speaker ${CASE_SUFFIX}','Audio category match','AUDIO',9900,2,TRUE,'ACTIVE',NOW() - INTERVAL '2 minutes'),
  ('${PRODUCT_F_ID}','${SELLER_ID}','Foxtrot Camera ${CASE_SUFFIX}','Different category item','CAMERAS',25900,4,TRUE,'ACTIVE',NOW() - INTERVAL '1 minute');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?category=AUDIO" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg match "$PRODUCT_E_ID" --arg other "$PRODUCT_F_ID" '
  type == "array" and
  (map(.id) | index($match)) != null and
  (map(.id) | index($other)) == null and
  all(.[]; .category == "AUDIO")
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:search_by_category_matching"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${PRODUCT_E_ID}','${PRODUCT_F_ID}'); DELETE FROM products WHERE id IN ('${PRODUCT_E_ID}','${PRODUCT_F_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
