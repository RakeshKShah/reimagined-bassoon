#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-browse-${CASE_SUFFIX}"
SELLER_ID="seller-browse-${CASE_SUFFIX}"
PRODUCT_A_ID="prod-001-${CASE_SUFFIX}"
PRODUCT_B_ID="prod-002-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/browse_all_products_includes_out_of_stock_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/browse_all_products_includes_out_of_stock_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${PRODUCT_A_ID}','${PRODUCT_B_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT_A_ID}','${PRODUCT_B_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','browse-all-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Browse All Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES
  ('${PRODUCT_A_ID}','${SELLER_ID}','Alpha Widget ${CASE_SUFFIX}','In stock browseable product','ELECTRONICS',1500,5,TRUE,'ACTIVE',NOW() - INTERVAL '2 minutes'),
  ('${PRODUCT_B_ID}','${SELLER_ID}','Beta Gadget ${CASE_SUFFIX}','Out of stock browseable product','ELECTRONICS',1800,0,TRUE,'ACTIVE',NOW() - INTERVAL '1 minute');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg a "$PRODUCT_A_ID" --arg b "$PRODUCT_B_ID" '
  type == "array" and
  (map(.id) | index($a)) != null and
  (map(.id) | index($b)) != null and
  (map(select(.id == $a))[0].stockQty == 5) and
  (map(select(.id == $b))[0].stockQty == 0) and
  (map(select(.id == $a))[0].category == "ELECTRONICS") and
  (map(select(.id == $b))[0].category == "ELECTRONICS")
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:browse_all_products_includes_out_of_stock"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${PRODUCT_A_ID}','${PRODUCT_B_ID}'); DELETE FROM products WHERE id IN ('${PRODUCT_A_ID}','${PRODUCT_B_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
