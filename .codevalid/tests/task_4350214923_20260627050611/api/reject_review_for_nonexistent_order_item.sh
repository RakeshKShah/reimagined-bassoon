#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer-77-${CASE_SUFFIX}@example.com"
PASSWORD="BuyerPass789!"
ORDER_ITEM_ID="nonexistent-item-999-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/reject_review_for_nonexistent_order_item_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/reject_review_for_nonexistent_order_item_${CASE_SUFFIX}.status"
BUYER_FILE="/tmp/reject_review_for_nonexistent_order_item_buyer_${CASE_SUFFIX}.json"
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
  --data "{\"order_item_id\":\"${ORDER_ITEM_ID}\",\"rating\":5,\"body\":\"Fake item\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
jq -e '.error == "Order item not found"' "$RESPONSE_FILE" >/dev/null
COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';")"
[ "$COUNT" = "0" ]

echo "CODEVALID_TEST_ASSERTION_OK:reject_review_for_nonexistent_order_item"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${BUYER_ID}';" >/dev/null
