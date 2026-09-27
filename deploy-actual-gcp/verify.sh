#!/usr/bin/env bash
set -uo pipefail

# Check a deployed Actual instance: it answers, it still has the settings that
# must not be undone, and whether its first account has been created.
#
#   ./verify.sh <project-id>
#
# One line per check: OK, KO (broken) or !! (needs action). Exits 1 on any KO.

PROJECT_ID="${1:-}"
REGION="${REGION:-europe-west9}"
SERVICE_NAME="actual-server"

if [[ -z "$PROJECT_ID" ]]; then
  echo "usage: $0 <project-id>" >&2
  exit 2
fi

SPEC="$(mktemp)"
trap 'rm -f "$SPEC"' EXIT
if ! gcloud run services describe "$SERVICE_NAME" --region="$REGION" \
     --project="$PROJECT_ID" --format=json > "$SPEC" 2>/dev/null; then
  echo "KO  service ${SERVICE_NAME} not found in ${PROJECT_ID} (${REGION})"
  exit 1
fi

python3 - "$SPEC" "$PROJECT_ID" <<'PY'
import json, sys
spec = json.load(open(sys.argv[1]))
project = sys.argv[2]
tpl = spec["spec"]["template"]
ann = tpl["metadata"].get("annotations", {})
c = tpl["spec"]["containers"][0]
env = {e["name"]: e.get("value", "") for e in c.get("env", [])}
st = spec.get("status", {})

failed = False

def check(ok, good, bad):
    global failed
    failed |= not ok
    print(("OK  " if ok else "KO  ") + (good if ok else bad))

print(f"OK  image {c['image']}")
check(ann.get("autoscaling.knative.dev/maxScale") == "1",
      "max-instances=1", f"max-instances={ann.get('autoscaling.knative.dev/maxScale')}: SQLite on gcsfuse cannot take two writers")
sa = tpl["spec"].get("serviceAccountName", "")
check(sa == f"actual-server-sa@{project}.iam.gserviceaccount.com",
      f"service account {sa}", f"service account {sa or 'default Compute'}: expected actual-server-sa")
check("169.254.0.0/16" in env.get("ACTUAL_TRUSTED_PROXIES", ""),
      "ACTUAL_TRUSTED_PROXIES includes the Cloud Run hop", "ACTUAL_TRUSTED_PROXIES lacks 169.254.0.0/16: every client shares one rate-limit bucket")
check(env.get("ACTUAL_TRUSTED_AUTH_PROXIES") == "::1/128",
      "ACTUAL_TRUSTED_AUTH_PROXIES=::1/128", f"ACTUAL_TRUSTED_AUTH_PROXIES={env.get('ACTUAL_TRUSTED_AUTH_PROXIES')!r}: header auth trusts more than loopback")
check(st.get("latestReadyRevisionName") == st.get("latestCreatedRevisionName"),
      f"latest revision serving ({st.get('latestReadyRevisionName')})",
      f"latest revision {st.get('latestCreatedRevisionName')} never became ready (serving {st.get('latestReadyRevisionName')}): read the logs")
sys.exit(1 if failed else 0)
PY
status=$?

URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"]["url"])' "$SPEC")"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 "$URL")"
if [[ "$code" == 200 ]]; then
  echo "OK  ${URL} answers 200"
else
  echo "KO  ${URL} answers ${code}"
  status=1
fi

bootstrapped="$(curl -s --max-time 30 "${URL}/account/needs-bootstrap" \
  | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["data"]["bootstrapped"]).lower())' 2>/dev/null)"
case "$bootstrapped" in
  true)  echo "OK  first account created" ;;
  false) echo "!!  no account yet: anyone reaching the URL can claim the instance -- the beneficiary must create theirs now" ;;
  *)     echo "!!  could not read /account/needs-bootstrap" ;;
esac

exit "$status"
