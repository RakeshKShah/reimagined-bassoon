#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-999-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_reviews_product_with_no_reviews_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_reviews_product_with_no_reviews_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW());

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'No Reviews Store ${CASE_SUFFIX}', '');

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'No Reviews Product', 'Product without reviews', 'general', 2500, 5, '[]', 'ACTIVE', true, NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'type == "array" and length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:get_reviews_product_with_no_reviews"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
