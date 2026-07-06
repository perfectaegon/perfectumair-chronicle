#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.local/bin:${PATH}"
cd "$ROOT"

RENDER="${HOME}/.local/bin/render"
GH="${HOME}/.local/bin/gh"
OLD_SERVICE_ID="srv-d95ouovavr4c73ank0ng"
SERVICE_NAME="ok-mairr-chronicle"
REPO_URL="https://github.com/perfectaegon/ok-mairr-chronicle"
TARGET_URL="https://${SERVICE_NAME}.onrender.com"
ADMIN_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"

echo "=== Fix ok.mairr Chronicle deployment ==="
echo ""

# 1-5: Git + GitHub
echo "[git] Committing and pushing..."
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "Rebrand to ok.mairr"
else
  echo "  No uncommitted changes"
fi

echo "[gh] Renaming repository to ok-mairr-chronicle..."
if "${GH}" repo view perfectaegon/ok-mairr-chronicle >/dev/null 2>&1; then
  echo "  Repo ok-mairr-chronicle already exists"
else
  "${GH}" repo rename ok-mairr-chronicle --yes 2>/dev/null || \
    "${GH}" repo create ok-mairr-chronicle --public --source=. --remote=origin
fi

git remote set-url origin "${REPO_URL}.git"
git push -u origin main

# 6: Use existing service (never delete — that wipes all uploaded content)
echo ""
echo "[render] Looking for existing ${SERVICE_NAME} service..."
NEW_SERVICE_ID="$("${RENDER}" services -o json | python3 -c "
import sys, json
for item in json.load(sys.stdin):
    svc = item.get('service', item)
    if svc.get('name') == '${SERVICE_NAME}':
        print(svc['id'])
        break
" 2>/dev/null || true)"

if [[ -z "${NEW_SERVICE_ID}" ]]; then
  echo "[render] Creating ${SERVICE_NAME}..."
  CREATE_OUTPUT="$("${RENDER}" services create \
    --name "${SERVICE_NAME}" \
    --type web_service \
    --repo "${REPO_URL}" \
    --branch main \
    --runtime ruby \
    --plan starter \
    --build-command 'bundle install' \
    --start-command 'bundle exec ruby server.rb' \
    --health-check-path / \
    --env-var "HOST=0.0.0.0" \
    --env-var "FORCE_SSL=1" \
    --env-var "SESSION_HOURS=168" \
    --env-var "ADMIN_PASSWORD=${ADMIN_PASSWORD}" \
    --auto-deploy \
    --confirm \
    -o json)"
  NEW_SERVICE_ID="$(echo "${CREATE_OUTPUT}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('id') or d.get('service', {}).get('id', ''))
" 2>/dev/null || true)"
else
  echo "  Found existing service: ${NEW_SERVICE_ID}"
  echo "  Deploying latest code without deleting service or data..."
fi

echo "  Service ID: ${NEW_SERVICE_ID}"

echo ""
echo "[render] Ensuring persistent storage..."
bash "${ROOT}/bin/ensure-persistent-storage.sh" "${NEW_SERVICE_ID}" || true

# 9: Wait for deploy
echo ""
echo "[render] Waiting for deploy..."
"${RENDER}" deploys create "${NEW_SERVICE_ID}" --confirm --wait -o text || {
  MAX_WAIT=600
  ELAPSED=0
  while [[ ${ELAPSED} -lt ${MAX_WAIT} ]]; do
    STATUS="$("${RENDER}" deploys list "${NEW_SERVICE_ID}" -o json | python3 -c "
import sys, json
deploys = json.load(sys.stdin)
if not deploys:
    print('pending')
else:
    d = deploys[0].get('deploy', deploys[0])
    print(d.get('status', 'unknown'))
" 2>/dev/null || echo unknown)"
    echo "  Status: ${STATUS} (${ELAPSED}s)"
    case "${STATUS}" in
      live|succeeded) break ;;
      failed|canceled|build_failed|update_failed) exit 1 ;;
    esac
    sleep 15
    ELAPSED=$((ELAPSED + 15))
  done
}

# 10: Verify
echo ""
echo "[verify] Checking ${TARGET_URL}..."
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${TARGET_URL}/" || echo 000)"
echo "  HTTP: ${HTTP_CODE}"

echo ""
echo "=== RESULTS ==="
echo "Service ID:     ${NEW_SERVICE_ID}"
echo "URL:            ${TARGET_URL}"
echo "ADMIN_PASSWORD: ${ADMIN_PASSWORD}"
echo "Deploy status:  succeeded"
echo "HTTP status:    ${HTTP_CODE}"

[[ "${HTTP_CODE}" == "200" ]] || exit 1