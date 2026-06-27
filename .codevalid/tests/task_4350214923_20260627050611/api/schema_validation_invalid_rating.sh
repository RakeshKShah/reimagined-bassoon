#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer-test-rating-${CASE_SUFFIX}@example.com"
PASSWORD="BuyerPass789!"
RESPONSE_FILE="/tmp/schema_validation_invalid_rating_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/schema_validation_invalid_rating_${CASE_SUFFIX}.status"
BUYER_FILE="/tmp/schema_validation_invalid_rating_buyer_${CASE_SUFFIX}.json"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$BUYER_FILE"; }
trap cleanup_files EXIT

# Given
curl -sS -o "$BUYER_FILE" \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}"
TOKEN="$(jq -r '.token' "$BUYER_FILE")"
BUYER_ID="$(jq -r '.user.id' "$BUYER_FILE")"
[ -n "$TOKEN" ]
[ "$TOKEN" != "null" ]
[ -n "$BUYER_ID" ]
[ "$BUYER_ID" != "null" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/reviews" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"order_item_id":"valid-id","rating":10,"body":"Test"}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
jq -e '.error | type == "string" and length > 0' "$RESPONSE_FILE" >/dev/null
COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM reviews WHERE buyer_id = '${BUYER_ID}';")"
[ "$COUNT" = "0" ]

echo "CODEVALID_TEST_ASSERTION_OK:schema_validation_invalid_rating"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${BUYER_ID}';" >/dev/null
