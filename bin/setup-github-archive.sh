#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

SERVICE_ID="${1:-srv-d95pgm5ckfvc73bkf8vg}"
GITHUB_REPO="${GITHUB_REPO:-perfectaegon/ok-mairr-chronicle}"
GITHUB_TOKEN="$("${HOME}/.local/bin/gh" auth token 2>/dev/null || true)"
API_KEY="$(python3 -c "
import pathlib, re
text = pathlib.Path('${HOME}/.render/cli.yaml').read_text()
match = re.search(r'^\\s*key:\\s*(\\S+)', text, re.M)
print(match.group(1) if match else '')
" 2>/dev/null || true)"

if [[ -z "${GITHUB_TOKEN}" ]]; then
  echo "Run: gh auth login"
  exit 1
fi

if [[ -z "${API_KEY}" ]]; then
  echo "Render API key not found."
  exit 1
fi

echo "Configuring GitHub archive on Render..."

curl -sS -X PUT "https://api.render.com/v1/services/${SERVICE_ID}/env-vars/GITHUB_TOKEN" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"value\":\"${GITHUB_TOKEN}\"}" >/dev/null

curl -sS -X PUT "https://api.render.com/v1/services/${SERVICE_ID}/env-vars/GITHUB_REPO" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"value\":\"${GITHUB_REPO}\"}" >/dev/null

echo "GITHUB_TOKEN and GITHUB_REPO set on Render."
echo "Publishing will now save posts and uploads to GitHub automatically."