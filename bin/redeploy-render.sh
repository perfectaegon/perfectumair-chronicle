#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.local/bin:${PATH}"
export CI=true
export RENDER_OUTPUT=json

RENDER="${HOME}/.local/bin/render"
OLD_SERVICE_ID="srv-d95ouovavr4c73ank0ng"
SERVICE_NAME="ok-mairr-chronicle"
REPO="https://github.com/perfectaegon/ok-mairr-chronicle"
BRANCH="main"
TARGET_URL="https://${SERVICE_NAME}.onrender.com"

# Generate secure admin password
ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"

echo "=== ok.mairr Chronicle Render Redeploy ==="
echo ""

# Step 1: Delete old service if it exists
echo "[1/5] Deleting old service ${OLD_SERVICE_ID} (if exists)..."
if "${RENDER}" services delete "${OLD_SERVICE_ID}" --confirm -o json 2>/dev/null; then
  echo "  Deleted ${OLD_SERVICE_ID}"
else
  echo "  Old service not found or already deleted, continuing"
fi

# Step 2: Create new service
echo ""
echo "[2/5] Creating new service ${SERVICE_NAME}..."
CREATE_OUTPUT="$("${RENDER}" services create \
  --name "${SERVICE_NAME}" \
  --type web_service \
  --repo "${REPO}" \
  --branch "${BRANCH}" \
  --runtime ruby \
  --plan free \
  --build-command "bundle install" \
  --start-command "bundle exec ruby server.rb" \
  --health-check-path "/" \
  --env-var "HOST=0.0.0.0" \
  --env-var "FORCE_SSL=1" \
  --env-var "SESSION_HOURS=168" \
  --env-var "ADMIN_PASSWORD=${ADMIN_PASSWORD}" \
  --confirm \
  -o json 2>&1)" || {
  echo "Create failed. Output:"
  echo "${CREATE_OUTPUT}"
  exit 1
}

NEW_SERVICE_ID="$(echo "${CREATE_OUTPUT}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id') or d.get('service',{}).get('id',''))" 2>/dev/null || true)"

if [[ -z "${NEW_SERVICE_ID}" ]]; then
  # Try to find service by name
  NEW_SERVICE_ID="$("${RENDER}" services list -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data:
    svc = item.get('service', item)
    if svc.get('name') == '${SERVICE_NAME}':
        print(svc['id'])
        break
" 2>/dev/null || true)"
fi

if [[ -z "${NEW_SERVICE_ID}" ]]; then
  echo "Could not determine new service ID. Raw output:"
  echo "${CREATE_OUTPUT}"
  exit 1
fi

echo "  New service ID: ${NEW_SERVICE_ID}"

# Step 3: Wait for deploy to succeed
echo ""
echo "[3/5] Waiting for deploy to succeed..."
MAX_WAIT=600
ELAPSED=0
DEPLOY_STATUS="unknown"

while [[ ${ELAPSED} -lt ${MAX_WAIT} ]]; do
  DEPLOY_JSON="$("${RENDER}" deploys list "${NEW_SERVICE_ID}" -o json 2>/dev/null | python3 -c "
import sys, json
deploys = json.load(sys.stdin)
if not deploys:
    print('none')
else:
    d = deploys[0].get('deploy', deploys[0])
    print(d.get('status', 'unknown'))
" 2>/dev/null || echo "unknown")"

  DEPLOY_STATUS="${DEPLOY_JSON}"
  echo "  Deploy status: ${DEPLOY_STATUS} (${ELAPSED}s elapsed)"

  case "${DEPLOY_STATUS}" in
    live|succeeded)
      DEPLOY_STATUS="succeeded"
      break
      ;;
    failed|canceled|build_failed|update_failed)
      echo "  Deploy failed!"
      "${RENDER}" deploys list "${NEW_SERVICE_ID}" -o json | head -c 2000
      exit 1
      ;;
  esac

  sleep 15
  ELAPSED=$((ELAPSED + 15))
done

if [[ "${DEPLOY_STATUS}" != "succeeded" ]]; then
  echo "  Timed out waiting for deploy (last status: ${DEPLOY_STATUS})"
  exit 1
fi

# Step 4: Verify HTTP 200
echo ""
echo "[4/5] Verifying ${TARGET_URL} returns HTTP 200..."
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${TARGET_URL}/" || echo "000")"
echo "  HTTP status: ${HTTP_CODE}"

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "  Health check failed (expected 200)"
  exit 1
fi

# Step 5: Report results
echo ""
echo "[5/5] Done!"
echo ""
echo "=== RESULTS ==="
echo "Service ID:    ${NEW_SERVICE_ID}"
echo "URL:           ${TARGET_URL}"
echo "ADMIN_PASSWORD: ${ADMIN_PASSWORD}"
echo "Deploy status: succeeded"
echo "HTTP status:   ${HTTP_CODE}"