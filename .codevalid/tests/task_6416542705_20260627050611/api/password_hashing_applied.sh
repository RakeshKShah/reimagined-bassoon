#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="hash-${CASE_SUFFIX}@example.com"
PASSWORD="PlainPassword123"
RESPONSE_FILE="/tmp/password_hashing_applied_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/password_hashing_applied_${CASE_SUFFIX}.status"
HASH_FILE="/tmp/password_hashing_applied_${CASE_SUFFIX}.txt"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$HASH_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}" > "$STATUS_FILE"
psql "$DATABASE_URL" -t -A -c "SELECT password_hash FROM users WHERE email = '${EMAIL}';" > "$HASH_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
STORED_HASH="$(tr -d '\n' < "$HASH_FILE")"
[ -n "$STORED_HASH" ]
[ "$STORED_HASH" != "$PASSWORD" ]
printf '%s' "$STORED_HASH" | grep -E '^\$2[aby]\$' >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:password_hashing_applied"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
