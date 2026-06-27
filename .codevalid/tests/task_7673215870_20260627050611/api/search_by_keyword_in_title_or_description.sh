#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-keyword-${CASE_SUFFIX}"
SELLER_ID="seller-keyword-${CASE_SUFFIX}"
PRODUCT_G_ID="prod-007-${CASE_SUFFIX}"
PRODUCT_H_ID="prod-008-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/search_by_keyword_in_title_or_description_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/search_by_keyword_in_title_or_description_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
DELETE FROM order_items WHERE product_id IN ('${PRODUCT_G_ID}','${PRODUCT_H_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT_G_ID}','${PRODUCT_H_ID}');
DELETE FROM sellers WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${SELLER_USER_ID}','keyword-${CASE_SUFFIX}@example.com','seed-hash','SELLER','ACTIVE');
INSERT INTO sellers (id, user_id, store_name)
VALUES ('${SELLER_ID}','${SELLER_USER_ID}','Keyword Store ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, visible, status, created_at)
VALUES
  ('${PRODUCT_G_ID}','${SELLER_ID}','Golf Club Set ${CASE_SUFFIX}','High-quality clubs for enthusiasts.','SPORTS',18900,1,TRUE,'ACTIVE',NOW() - INTERVAL '2 minutes'),
  ('${PRODUCT_H_ID}','${SELLER_ID}','Hotel Reservation Guide ${CASE_SUFFIX}','How to book hotels worldwide.','BOOKS',2500,0,TRUE,'ACTIVE',NOW() - INTERVAL '1 minute');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  "$BASE_URL/products?keyword=club" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e --arg match "$PRODUCT_G_ID" --arg other "$PRODUCT_H_ID" '
  type == "array" and
  (map(.id) | index($match)) != null and
  (map(.id) | index($other)) == null
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:search_by_keyword_in_title_or_description"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE product_id IN ('${PRODUCT_G_ID}','${PRODUCT_H_ID}'); DELETE FROM products WHERE id IN ('${PRODUCT_G_ID}','${PRODUCT_H_ID}'); DELETE FROM sellers WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null
