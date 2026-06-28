#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-${CASE_SUFFIX}@example.com"
PASSWORD="SellerPass123!"
STORE_NAME="My Awesome Store ${CASE_SUFFIX}"
BIO="Handmade crafts and vintage finds ${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_signup_creates_store_profile_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_signup_creates_store_profile_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"${BIO}\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
jq -e '.token | type == "string" and length > 10' "$RESPONSE_FILE" >/dev/null
jq -e --arg email "$EMAIL" --arg storeName "$STORE_NAME" --arg bio "$BIO" '
  .user.email == $email and
  .user.role == "SELLER" and
  .user.status == "PENDING" and
  .user.sellerProfile.storeName == $storeName and
  .user.sellerProfile.bio == $bio and
  (.user.id | type == "string" and length > 0) and
  (.user.sellerProfile.id | type == "string" and length > 0)
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_signup_creates_store_profile"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null
