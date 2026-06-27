#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-codevalid-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_ID="user-seller-1-${CASE_SUFFIX}"
SELLER_EMAIL="seller-role-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/checkout_role_non_buyer_forbidden_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_role_non_buyer_forbidden_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: process.argv[2], role: 'SELLER', status: 'ACTIVE'}, process.argv[3]));" "$SELLER_ID" "$SELLER_EMAIL" "$JWT_SECRET")"

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM "SellerProfile" WHERE "userId" = '$SELLER_ID';
DELETE FROM "User" WHERE id = '$SELLER_ID';
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('$SELLER_ID', '$SELLER_EMAIL', 'hashed-password', 'SELLER', 'ACTIVE', NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/checkout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"items":[{"product_id":"prod-100-forbidden","qty":1}]}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Forbidden"' "$RESPONSE_FILE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:checkout_role_non_buyer_forbidden"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "SellerProfile" WHERE "userId" = '$SELLER_ID';
DELETE FROM "User" WHERE id = '$SELLER_ID';
SQL
