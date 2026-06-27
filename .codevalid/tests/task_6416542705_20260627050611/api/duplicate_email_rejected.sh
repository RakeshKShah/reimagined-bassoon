#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="existing-${CASE_SUFFIX}@example.com"
PASSWORD="AnyPass123!"
SEEDED_HASH='$2b$10$abcdefghijklmnopqrstuu0C6bNEOit1vKx6U.7D/6nM9l8QhD1QK'
RESPONSE_FILE="/tmp/duplicate_email_rejected_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/duplicate_email_rejected_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('dup-${CASE_SUFFIX}', '${EMAIL}', '${SEEDED_HASH}', 'SELLER', 'PENDING', NOW());" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Second Store ${CASE_SUFFIX}\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
jq -e '.error == "Email already registered"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:duplicate_email_rejected"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
