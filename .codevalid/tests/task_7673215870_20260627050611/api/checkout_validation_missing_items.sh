#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="user-buyer-validation-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-validation-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/checkout_validation_missing_items_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_validation_missing_items_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'BUYER', status: 'ACTIVE'}, process.argv[3]));" "$BUYER_ID" "$BUYER_EMAIL" "$JWT_SECRET")"

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM "Order" WHERE "buyerId" = '$BUYER_ID';
DELETE FROM "User" WHERE id = '$BUYER_ID';
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('$BUYER_ID', '$BUYER_EMAIL', 'hashed-password', 'BUYER', 'ACTIVE', NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
if grep -F '"error"' "$RESPONSE_FILE" >/dev/null || grep -F 'items' "$RESPONSE_FILE" >/dev/null; then :; else exit 1; fi
ORDER_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM \"Order\" WHERE \"buyerId\" = '$BUYER_ID';")"
[ "$ORDER_COUNT" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:checkout_validation_missing_items"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "Order" WHERE "buyerId" = '$BUYER_ID';
DELETE FROM "User" WHERE id = '$BUYER_ID';
SQL
