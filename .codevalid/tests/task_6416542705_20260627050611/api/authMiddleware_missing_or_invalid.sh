#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/authMiddleware_missing_or_invalid_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/authMiddleware_missing_or_invalid_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given — no authentication header or session is provided
: "Unauthenticated request"

# When — request seller dashboard without auth
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" > "$STATUS_FILE"

# Then — verify auth middleware rejects the request
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "401" ]
grep -E '"error":"(Authentication required|Unauthorized|Invalid token)"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:authMiddleware_missing_or_invalid"
