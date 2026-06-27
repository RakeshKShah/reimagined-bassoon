#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/invalid_email_format_validation_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/invalid_email_format_validation_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
: "No persistent setup required for validation-only request"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data '{"email":"not-an-email","password":"EmailPass123!","role":"BUYER"}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
jq -e '.error | type == "string" and ((ascii_downcase | contains("email")) or contains("Invalid email"))' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:invalid_email_format_validation"

# Cleanup
: "No cleanup required for stateless validation failure"
