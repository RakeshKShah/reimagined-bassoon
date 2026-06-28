#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/missing_required_field_validation_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/missing_required_field_validation_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
: "No persistent setup required for validation-only request"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data '{"password":"NoEmailPass!","role":"BUYER"}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
jq -e '.error | type == "string" and (ascii_downcase | contains("email"))' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:missing_required_field_validation"

# Cleanup
: "No cleanup required for stateless validation failure"
