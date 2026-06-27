#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-missing-status-${CASE_SUFFIX}"
SELLER_ID="seller-missing-status-${CASE_SUFFIX}"
EMAIL="missing-status-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/missing_status_field_validation_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/missing_status_field_validation_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given — create a seller for missing-field validation
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('${USER_ID}', '${EMAIL}', 'seed-hash', 'SELLER', 'PENDING', NOW());"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Missing Status Store ${CASE_SUFFIX}', 'Validation target');"

# When — submit an empty request body without status
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  --data '{}' > "$STATUS_FILE"

# Then — verify required-field validation and unchanged database state
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F '"error"' "$RESPONSE_FILE" >/dev/null
USER_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id = '${USER_ID}';")"
[ "$USER_STATUS" = "PENDING" ]

echo "CODEVALID_TEST_ASSERTION_OK:missing_status_field_validation"

# Cleanup — handled by trap to remove seeded seller profile and user
