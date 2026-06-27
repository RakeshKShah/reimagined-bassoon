#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/unauthenticated_no_session_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/unauthenticated_no_session_${CASE_SUFFIX}.status"
trap 'rm -f "$RESPONSE_FILE" "$STATUS_FILE"' EXIT

# Given — no authentication token or session is provided

# When — attempt to create a product without authentication
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  --data '{"title":"Test Product","description":"Test","category":"Test","price_cents":1000,"stock_qty":5,"photos":[]}' > "$STATUS_FILE"

# Then — verify requireAuth rejects the request
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "401" ]
grep -E '"error":"(Unauthorized|Invalid token)"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_no_session"
