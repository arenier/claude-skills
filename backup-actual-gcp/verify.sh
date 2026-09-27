#!/usr/bin/env bash
set -uo pipefail

# Check that a backup is not only healthy but current.
#
#   ./verify.sh <source-project> <backup-project>
#
# A stale copy is structurally sound: `PRAGMA integrity_check` answers ok on a
# backup that stopped refreshing weeks ago. So this checks three things:
#   1. the last job execution succeeded, and how recently
#   2. every source object is in the backup with the same MD5 -- an object
#      changed since the last successful run is expected to differ, any other
#      difference means the copy is broken
#   3. the SQLite files in the backup pass integrity_check (if sqlite3 exists)
# One line per check: OK, KO or !!. Exits 1 on any KO.

SOURCE_PROJECT="${1:-}"
BACKUP_PROJECT="${2:-${BACKUP_PROJECT:-}}"
REGION="${REGION:-europe-west9}"
SERVICE_NAME="${SERVICE_NAME:-actual-server}"

if [[ -z "$SOURCE_PROJECT" || -z "$BACKUP_PROJECT" ]]; then
  echo "usage: $0 <source-project> <backup-project>" >&2
  exit 2
fi

SOURCE_BUCKET="${SOURCE_BUCKET:-$(gcloud run services describe "$SERVICE_NAME" \
  --project="$SOURCE_PROJECT" --region="$REGION" \
  --format='value(spec.template.spec.volumes[0].csi.volumeAttributes.bucketName)' 2>/dev/null)}"
DEST_BUCKET="actual-backup-${SOURCE_PROJECT}"
JOB_NAME="actual-backup-${SOURCE_PROJECT}"

if [[ -z "$SOURCE_BUCKET" ]]; then
  echo "KO  no Cloud Storage volume on ${SERVICE_NAME} in ${SOURCE_PROJECT}: pass SOURCE_BUCKET=..."
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

gcloud run jobs executions list --job="$JOB_NAME" --region="$REGION" \
  --project="$BACKUP_PROJECT" --limit=10 --format=json > "$TMP/executions.json" 2>/dev/null \
  || echo '[]' > "$TMP/executions.json"
gcloud storage objects list "gs://${SOURCE_BUCKET}" --project="$SOURCE_PROJECT" \
  --format=json > "$TMP/source.json" 2>/dev/null || echo '[]' > "$TMP/source.json"
gcloud storage objects list "gs://${DEST_BUCKET}" --project="$BACKUP_PROJECT" \
  --format=json > "$TMP/dest.json" 2>/dev/null || echo '[]' > "$TMP/dest.json"

python3 - "$TMP" <<'PY'
import json, re, sys
from datetime import datetime, timezone
from pathlib import Path

tmp = Path(sys.argv[1])
failed = False

def ts(value):
    """Parse the timestamp shapes gcloud emits, on Python 3.9 too."""
    if not value:
        return None
    v = value.replace("Z", "+00:00")
    v = re.sub(r"([+-]\d\d)(\d\d)$", r"\1:\2", v)
    v = re.sub(r"\.(\d+)", lambda m: "." + m.group(1)[:6].ljust(6, "0"), v)
    return datetime.fromisoformat(v)

def line(kind, text):
    global failed
    failed |= kind == "KO"
    print(f"{kind}  {text}")

executions = json.loads((tmp / "executions.json").read_text())
def started(e):
    s = e.get("status", {})
    return ts(s.get("startTime") or e.get("metadata", {}).get("creationTimestamp"))
executions.sort(key=lambda e: started(e) or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
succeeded = [e for e in executions if e.get("status", {}).get("succeededCount")]
last_success = started(succeeded[0]) if succeeded else None

if not executions:
    line("KO", "no job execution found: the backup has never run")
else:
    last = executions[0]
    when = started(last)
    if last.get("status", {}).get("succeededCount"):
        age = datetime.now(timezone.utc) - when
        line("OK" if age.days < 2 else "KO", f"last execution succeeded {when:%Y-%m-%d %H:%M} UTC ({age.days} day(s) ago)")
    else:
        line("KO", f"last execution {when:%Y-%m-%d %H:%M} UTC failed -- nobody is notified of a failed job")
    fails = sum(1 for e in executions if e.get("status", {}).get("failedCount"))
    if fails:
        line("!!", f"{fails} of the last {len(executions)} executions failed")

def objects(name):
    out = {}
    for o in json.loads((tmp / name).read_text()):
        key = o.get("name") or o.get("url", "").split("/", 3)[-1]
        out[key] = (o.get("md5_hash") or o.get("md5Hash"), ts(o.get("update_time") or o.get("updated")))
    return out

source, dest = objects("source.json"), objects("dest.json")
if not source:
    line("KO", "source bucket empty or unreadable")
same, changed_since, broken = 0, [], []
for key, (md5, updated) in source.items():
    if key in dest and dest[key][0] == md5:
        same += 1
    elif last_success and updated and updated > last_success:
        changed_since.append(key)
    else:
        broken.append(key)
if source:
    line("OK" if not broken else "KO", f"{same}/{len(source)} source objects identical in the backup")
for key in broken:
    line("KO", f"  {key}: {'missing' if key not in dest else 'different'} although unchanged since the last successful run")
if changed_since:
    line("!!", f"{len(changed_since)} object(s) changed since the last successful run, copied at the next one")
sys.exit(1 if failed else 0)
PY
status=$?

if command -v sqlite3 >/dev/null 2>&1; then
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    gcloud storage cp "$url" "$TMP/check.sqlite" --project="$BACKUP_PROJECT" >/dev/null 2>&1 || continue
    result="$(sqlite3 "$TMP/check.sqlite" 'PRAGMA integrity_check;' 2>&1)"
    if [[ "$result" == ok ]]; then
      echo "OK  integrity_check ${url##*/}"
    else
      echo "KO  integrity_check ${url##*/}: ${result}"
      status=1
    fi
  done < <(gcloud storage ls "gs://${DEST_BUCKET}/**.sqlite" --project="$BACKUP_PROJECT" 2>/dev/null)
else
  echo "!!  sqlite3 not installed: integrity_check skipped"
fi

exit "$status"
