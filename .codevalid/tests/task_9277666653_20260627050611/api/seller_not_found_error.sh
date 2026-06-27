#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_ID="nonexistent-seller-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_not_found_error_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_not_found_error_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given — use an isolated seller id that does not exist
:

# When — attempt to update a non-existent seller
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  --data '{"status":"ACTIVE"}' > "$STATUS_FILE"

# Then — verify 404 not found response
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Seller not found"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_not_found_error"
