#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="token-${CASE_SUFFIX}@example.com"
PASSWORD="TokenPass123!"
STORE_NAME="Token Store ${CASE_SUFFIX}"
BIO="Bio for token ${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/token_generation_includes_claims_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/token_generation_includes_claims_${CASE_SUFFIX}.status"
PAYLOAD_FILE="/tmp/token_generation_includes_claims_${CASE_SUFFIX}.payload.json"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$PAYLOAD_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"${BIO}\"}" > "$STATUS_FILE"
TOKEN="$(jq -r '.token' "$RESPONSE_FILE")"
PAYLOAD_B64="$(printf '%s' "$TOKEN" | cut -d '.' -f2 | tr '_-' '/+')"
PAD=$(( (4 - ${#PAYLOAD_B64} % 4) % 4 ))
while [ "$PAD" -gt 0 ]; do PAYLOAD_B64="${PAYLOAD_B64}="; PAD=$((PAD - 1)); done
printf '%s' "$PAYLOAD_B64" | base64 -d > "$PAYLOAD_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
jq -e --arg email "$EMAIL" '
  .user.email == $email and
  .user.role == "SELLER" and
  .user.status == "PENDING" and
  (.user.sellerProfile.id | type == "string" and length > 0)
' "$RESPONSE_FILE" >/dev/null
EXPECTED_USER_ID="$(jq -r '.user.id' "$RESPONSE_FILE")"
EXPECTED_SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$RESPONSE_FILE")"
jq -e --arg id "$EXPECTED_USER_ID" --arg email "$EMAIL" --arg sellerProfileId "$EXPECTED_SELLER_PROFILE_ID" '
  .id == $id and
  .email == $email and
  .role == "SELLER" and
  .status == "PENDING" and
  .sellerProfileId == $sellerProfileId
' "$PAYLOAD_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:token_generation_includes_claims"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
