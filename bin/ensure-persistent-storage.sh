#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

RENDER="${HOME}/.local/bin/render"
SERVICE_ID="${1:-srv-d95pgm5ckfvc73bkf8vg}"
MOUNT_PATH="/opt/render/project/src/data"
API_KEY="$(python3 -c "
import pathlib, re
text = pathlib.Path('${HOME}/.render/cli.yaml').read_text()
match = re.search(r'^\\s*key:\\s*(\\S+)', text, re.M)
print(match.group(1) if match else '')
" 2>/dev/null || true)"

if [[ -z "${API_KEY}" ]]; then
  echo "Render API key not found. Add a persistent disk manually:"
  echo "  Dashboard → ok-mairr-chronicle → Disks → Add disk"
  echo "  Mount path: ${MOUNT_PATH}"
  echo "  Size: 1 GB"
  exit 1
fi

echo "=== Ensure persistent storage for ok.mairr Chronicle ==="
echo ""

echo "[render] Upgrading service to Starter plan (required for persistent disk)..."
if ! "${RENDER}" services update "${SERVICE_ID}" --plan starter --confirm -o text; then
  echo ""
  echo "Could not upgrade automatically. Add a payment method, then in the Render Dashboard:"
  echo "  1. Open https://dashboard.render.com/web/${SERVICE_ID}"
  echo "  2. Settings → Instance Type → choose Starter"
  echo "  3. Disks → Add Disk → mount path: ${MOUNT_PATH}, size: 1 GB"
  echo "  4. Manual Deploy → Deploy latest commit"
  echo ""
fi

echo ""
echo "[render] Checking for existing disk..."
EXISTING_DISK="$(curl -sS -H "Authorization: Bearer ${API_KEY}" \
  "https://api.render.com/v1/services/${SERVICE_ID}/disks" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(0)
for item in data:
    disk = item.get('disk', item)
    print(disk.get('id', ''))
    break
" 2>/dev/null || true)"

if [[ -n "${EXISTING_DISK}" ]]; then
  echo "  Disk already attached: ${EXISTING_DISK}"
else
  echo "[render] Attaching 1 GB persistent disk at ${MOUNT_PATH}..."
  curl -sS -X POST "https://api.render.com/v1/disks" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"chronicle-data\",\"sizeGB\":1,\"mountPath\":\"${MOUNT_PATH}\",\"serviceId\":\"${SERVICE_ID}\"}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('  Disk ID:', d.get('id', d))"
fi

echo ""
echo "[render] Deploying..."
"${RENDER}" deploys create "${SERVICE_ID}" --confirm --wait -o text

echo ""
echo "Persistent storage is configured."
echo "Your posts and uploads will now survive future deploys."