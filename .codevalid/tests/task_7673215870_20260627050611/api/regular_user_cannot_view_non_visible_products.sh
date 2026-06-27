#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-regular-view-${CASE_SUFFIX}"
SELLER_ID="seller-regular-view-${CASE_SUFFIX}"
HIDDEN_ID="prod-070-${CASE_SUFFIX}"
VISIBLE_ID="prod-071-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/regular_user_cannot_view_non_visible_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/regular_user_cannot_view_non_visible_products_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${HIDDEN_ID}','${VISIBLE_ID}');
DELETE FROM products WHERE id IN ('${HIDDEN_ID}','${VISIBLE_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','regular-view-seller-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Regular View Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status)
VALUES
  ('${HIDDEN_ID}','${SELLER_ID}','Hidden Product ${CASE_SUFFIX}','Hidden listing','general',3100,1,FALSE,'ACTIVE'),
  ('${VISIBLE_ID}','${SELLER_ID}','Visible Product ${CASE_SUFFIX}','Visible listing','general',3200,2,TRUE,'ACTIVE');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg hidden "$HIDDEN_ID" --arg visible "$VISIBLE_ID" '
  type == "array" and
  (map(.id) | index($visible)) != null and
  (map(.id) | index($hidden)) == null
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:regular_user_cannot_view_non_visible_products"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${HIDDEN_ID}','${VISIBLE_ID}'); DELETE FROM products WHERE id IN ('${HIDDEN_ID}','${VISIBLE_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
