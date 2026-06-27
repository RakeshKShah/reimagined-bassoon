#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="user-buyer-12-${CASE_SUFFIX}"
BUYER_EMAIL="checkout-invalid-schema-${CASE_SUFFIX}@example.com"
RESP1="/tmp/checkout_invalid_request_schema_1_${CASE_SUFFIX}.json"
RESP2="/tmp/checkout_invalid_request_schema_2_${CASE_SUFFIX}.json"
RESP3="/tmp/checkout_invalid_request_schema_3_${CASE_SUFFIX}.json"
STATUS1="/tmp/checkout_invalid_request_schema_1_${CASE_SUFFIX}.status"
STATUS2="/tmp/checkout_invalid_request_schema_2_${CASE_SUFFIX}.status"
STATUS3="/tmp/checkout_invalid_request_schema_3_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESP1" "$RESP2" "$RESP3" "$STATUS1" "$STATUS2" "$STATUS3"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${BUYER_ID}' OR email = '${BUYER_EMAIL}'; INSERT INTO users (id, email, password_hash, role, status) VALUES ('${BUYER_ID}','${BUYER_EMAIL}','seed-hash','BUYER','ACTIVE');" >/dev/null
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'BUYER', status: 'ACTIVE'}, process.argv[3]));" "$BUYER_ID" "$BUYER_EMAIL" "$JWT_SECRET")"

# When
curl -sS -o "$RESP1" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"items":"invalid"}' > "$STATUS1"
curl -sS -o "$RESP2" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"items":[]}' > "$STATUS2"
curl -sS -o "$RESP3" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{}' > "$STATUS3"

# Then
S1="$(cat "$STATUS1")"
S2="$(cat "$STATUS2")"
S3="$(cat "$STATUS3")"
[ "$S1" = "400" ]
[ "$S2" = "400" ]
[ "$S3" = "400" ]
jq -e 'has("error") or has("message")' "$RESP1" >/dev/null
jq -e 'has("error") or has("message")' "$RESP2" >/dev/null
jq -e 'has("error") or has("message")' "$RESP3" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:checkout_invalid_request_schema"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${BUYER_ID}' OR email = '${BUYER_EMAIL}';" >/dev/null
