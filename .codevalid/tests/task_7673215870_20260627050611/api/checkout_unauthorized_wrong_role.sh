#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="user-seller-1-${CASE_SUFFIX}"
SELLER_EMAIL="checkout-wrong-role-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/checkout_unauthorized_wrong_role_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_unauthorized_wrong_role_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${SELLER_USER_ID}' OR email = '${SELLER_EMAIL}'; INSERT INTO users (id, email, password_hash, role, status) VALUES ('${SELLER_USER_ID}','${SELLER_EMAIL}','seed-hash','SELLER','ACTIVE');" >/dev/null
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'SELLER', status: 'ACTIVE'}, process.argv[3]));" "$SELLER_USER_ID" "$SELLER_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"items":[{"product_id":"prod-any-02","qty":1}]}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
jq -e '.error == "Forbidden"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:checkout_unauthorized_wrong_role"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${SELLER_USER_ID}' OR email = '${SELLER_EMAIL}';" >/dev/null
