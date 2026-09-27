#!/usr/bin/env bash
set -uo pipefail

# Check a deployed FreshRSS instance end to end: the settings that must not be
# undone, no secret in the spec, the service answering, the scheduler enabled,
# and one real refresh run.
#
#   ./verify.sh <project-id> [--no-refresh]
#
# One line per check: OK, KO (broken) or !! (needs a look). Exits 1 on any KO.

PROJECT_ID="${1:-}"
REFRESH=true
[[ "${2:-}" == "--no-refresh" ]] && REFRESH=false
REGION="${REGION:-europe-west9}"
SERVICE_NAME="freshrss"
JOB_NAME="freshrss-refresh"

if [[ -z "$PROJECT_ID" ]]; then
  echo "usage: $0 <project-id> [--no-refresh]" >&2
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
ports = [p.get("containerPort") for p in c.get("ports", [])]
st = spec.get("status", {})
failed = False

def check(ok, good, bad):
    global failed
    failed |= not ok
    print(("OK  " if ok else "KO  ") + (good if ok else bad))

print(f"OK  image {c['image']}")
check(ann.get("autoscaling.knative.dev/maxScale") == "1",
      "max-instances=1", f"max-instances={ann.get('autoscaling.knative.dev/maxScale')}: SQLite on gcsfuse cannot take two writers")
check(ann.get("run.googleapis.com/execution-environment") == "gen2",
      "gen2 execution environment", "not gen2: Cloud Storage volumes need it")
check(ports == [80], "port 80", f"ports {ports}: the image listens on 80")
check("PORT" not in env, "no PORT variable", "PORT is set: reserved by Cloud Run")
sa = tpl["spec"].get("serviceAccountName", "")
check(sa == f"freshrss-sa@{project}.iam.gserviceaccount.com",
      f"service account {sa}", f"service account {sa or 'default Compute'}: expected freshrss-sa")
check("169.254.0.0/16" in env.get("TRUSTED_PROXY", ""),
      "TRUSTED_PROXY includes the Cloud Run hop", "TRUSTED_PROXY lacks 169.254.0.0/16: logs show Google's proxy, not the client")
user = env.get("FRESHRSS_USER", "")
check("$ADMIN_PASSWORD" in user and "$REFRESH_TOKEN" in user,
      "no secret in the spec (FRESHRSS_USER holds placeholders)", "FRESHRSS_USER does not hold $ADMIN_PASSWORD / $REFRESH_TOKEN placeholders: a secret may be in the spec")
check(st.get("latestReadyRevisionName") == st.get("latestCreatedRevisionName"),
      f"latest revision serving ({st.get('latestReadyRevisionName')})",
      f"latest revision {st.get('latestCreatedRevisionName')} never became ready: read the logs")
sys.exit(1 if failed else 0)
PY
status=$?

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
BASE_URL="https://${SERVICE_NAME}-${PROJECT_NUMBER}.${REGION}.run.app"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 90 "${BASE_URL}/api/")"
if [[ "$code" == 200 ]]; then
  echo "OK  ${BASE_URL}/api/ answers 200"
else
  echo "KO  ${BASE_URL}/api/ answers ${code}"
  status=1
fi

state="$(gcloud scheduler jobs describe "${JOB_NAME}-hourly" --location="$REGION" \
  --project="$PROJECT_ID" --format='value(state)' 2>/dev/null)"
if [[ "$state" == ENABLED ]]; then
  echo "OK  scheduler ${JOB_NAME}-hourly enabled"
else
  echo "KO  scheduler ${JOB_NAME}-hourly: ${state:-missing}"
  status=1
fi

if [[ "$REFRESH" == true ]]; then
  if gcloud run jobs execute "$JOB_NAME" --region="$REGION" --project="$PROJECT_ID" --wait >/dev/null 2>&1; then
    echo "OK  refresh job ran end to end"
  else
    echo "KO  refresh job failed -- with the service answering, almost always a token/user mismatch"
    echo "      gcloud logging read 'resource.labels.job_name=${JOB_NAME}' --project=${PROJECT_ID} --limit=20"
    status=1
  fi
fi

exit "$status"
