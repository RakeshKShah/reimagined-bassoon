#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-null-status-${CASE_SUFFIX}"
SELLER_ID="seller-null-status-${CASE_SUFFIX}"
EMAIL="null-status-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/malformed_request_body_error_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/malformed_request_body_error_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create a seller for invalid-type validation
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('${USER_ID}', '${EMAIL}', 'seed-hash', 'SELLER', 'PENDING', NOW());"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Null Status Store ${CASE_SUFFIX}', 'Validation target');"

# When — submit a malformed semantic body with null status
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  --data '{"status":null}' > "$STATUS_FILE"

# Then — verify validation error and unchanged DB state
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F '"error"' "$RESPONSE_FILE" >/dev/null
USER_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id = '${USER_ID}';")"
[ "$USER_STATUS" = "PENDING" ]

echo "CODEVALID_TEST_ASSERTION_OK:malformed_request_body_error"

# Cleanup — handled by trap to remove seeded seller profile and user
