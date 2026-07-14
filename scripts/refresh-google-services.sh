#!/usr/bin/env bash
# Re-download android/app/google-services.json after Firebase Auth / SHA changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_ID="1:768748224321:android:2ef77f7bc86ecb080fabc0"
PROJECT="roomcraft-e1312"
OUT="android/app/google-services.json"

if [ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  if [ -f .secrets/roomcraft-e1312-firebase-adminsdk-fbsvc-2e5c8dfb7c.json ]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$ROOT/.secrets/roomcraft-e1312-firebase-adminsdk-fbsvc-2e5c8dfb7c.json"
  fi
fi

npx --yes firebase-tools@15 apps:sdkconfig ANDROID "$APP_ID" \
  --project "$PROJECT" --out "$OUT"

echo "Wrote $OUT"
python3 - <<'PY'
import json
from pathlib import Path
p = Path("android/app/google-services.json")
d = json.loads(p.read_text())
oauth = d["client"][0].get("oauth_client") or []
print(f"oauth_client entries: {len(oauth)}")
for c in oauth:
    print(f"  type={c.get('client_type')} id={c.get('client_id','')[:40]}...")
if not oauth:
    print("WARNING: oauth_client still empty.")
    print("Open Firebase Authentication → Get started → enable Google provider, then re-run.")
else:
    web = [c for c in oauth if c.get("client_type") == 3]
    if web:
        print("Web client (serverClientId) candidate:")
        print(web[0]["client_id"])
        print("Set: gh secret set ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID --repo tmai-tech/RoomCraft --body '<id above>'")
PY
