#!/usr/bin/env bash
set -euo pipefail

# Set up a scheduled backup of one Actual instance into the central backup
# project.
#
#   ./add-instance.sh <source-project> <backup-project>
#
# Copies the instance's Cloud Storage bucket into a dedicated bucket in the
# backup project. No credential of the beneficiary is involved: the copy uses
# your own GCP access to the bucket, not the Actual server's password.
#
# Idempotent: re-running updates the job and the schedule in place.

SOURCE_PROJECT="${1:-}"
BACKUP_PROJECT="${2:-${BACKUP_PROJECT:-}}"
REGION="${REGION:-europe-west9}"
SCHEDULE="${SCHEDULE:-0 3 * * *}"
TIMEZONE="${TIMEZONE:-Europe/Paris}"
SERVICE_NAME="${SERVICE_NAME:-actual-server}"
KEEP_DAYS="${KEEP_DAYS:-30}"
KEEP_VERSIONS="${KEEP_VERSIONS:-3}"

if [[ -z "$SOURCE_PROJECT" || -z "$BACKUP_PROJECT" ]]; then
  echo "usage: $0 <source-project> <backup-project>" >&2
  echo "  env: REGION SCHEDULE TIMEZONE SERVICE_NAME SOURCE_BUCKET" >&2
  echo "       KEEP_DAYS KEEP_VERSIONS" >&2
  exit 1
fi

# Read the bucket straight off the running service, so a backup can never be
# pointed at the wrong one.
SOURCE_BUCKET="${SOURCE_BUCKET:-$(gcloud run services describe "$SERVICE_NAME" \
  --project="$SOURCE_PROJECT" --region="$REGION" \
  --format='value(spec.template.spec.volumes[0].csi.volumeAttributes.bucketName)' 2>/dev/null)}"

if [[ -z "$SOURCE_BUCKET" ]]; then
  echo "error: no Cloud Storage volume found on ${SERVICE_NAME} in ${SOURCE_PROJECT}." >&2
  echo "  pass it explicitly: SOURCE_BUCKET=... $0 $SOURCE_PROJECT $BACKUP_PROJECT" >&2
  exit 1
fi

SLUG="$SOURCE_PROJECT"
DEST_BUCKET="actual-backup-${SLUG}"
JOB_NAME="actual-backup-${SLUG}"
SA_NAME="$(printf 'backup-%s-sa' "$SLUG" | cut -c1-30)"
SA_EMAIL="${SA_NAME}@${BACKUP_PROJECT}.iam.gserviceaccount.com"
SCHEDULER_SA_EMAIL="backup-scheduler-sa@${BACKUP_PROJECT}.iam.gserviceaccount.com"
IMAGE="gcr.io/google.com/cloudsdktool/google-cloud-cli:stable"

echo "Source:      ${SOURCE_PROJECT} / gs://${SOURCE_BUCKET}"
echo "Destination: ${BACKUP_PROJECT} / gs://${DEST_BUCKET}"
echo "Schedule:    ${SCHEDULE} (${TIMEZONE})"
echo ""

LIFECYCLE="$(mktemp)"
trap 'rm -f "$LIFECYCLE"' EXIT
# Delete a superseded version once it is both old enough and no longer among
# the most recent ones. Conditions are ANDed, so a handful of recent versions
# always survive regardless of age.
cat > "$LIFECYCLE" <<EOF
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {
        "isLive": false,
        "daysSinceNoncurrentTime": ${KEEP_DAYS},
        "numNewerVersions": ${KEEP_VERSIONS}
      }
    }
  ]
}
EOF

# --- Source bucket: versioning ------------------------------------------------
# Protects against an in-place overwrite or corruption, independently of the
# copy below. Cheap: these files are kilobytes to a few megabytes.
echo "Enabling versioning on the source bucket..."
gcloud storage buckets update "gs://${SOURCE_BUCKET}" \
  --versioning --lifecycle-file="$LIFECYCLE" --project="$SOURCE_PROJECT"

# --- Destination bucket -------------------------------------------------------
if ! gcloud storage buckets describe "gs://${DEST_BUCKET}" \
     --project="$BACKUP_PROJECT" >/dev/null 2>&1; then
  echo "Creating gs://${DEST_BUCKET}..."
  gcloud storage buckets create "gs://${DEST_BUCKET}" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --project="$BACKUP_PROJECT"
fi

gcloud storage buckets update "gs://${DEST_BUCKET}" \
  --versioning --lifecycle-file="$LIFECYCLE" --project="$BACKUP_PROJECT"

# --- Service account ----------------------------------------------------------
if ! gcloud iam service-accounts describe "$SA_EMAIL" \
     --project="$BACKUP_PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Actual backup: ${SLUG}" \
    --project="$BACKUP_PROJECT"
fi

# A freshly created service account is not immediately usable in IAM bindings.
grant_with_retry() {
  local i
  for i in $(seq 1 12); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 10
  done
  echo "error: IAM binding still failing after 2 minutes: $*" >&2
  return 1
}

# Read-only on the source: the backup job must never be able to alter the live
# budget it is protecting.
#
# bucketViewer is required alongside objectViewer. rsync reads bucket metadata
# before listing, and objectViewer does NOT carry storage.buckets.get -- the
# job fails with "does not have storage.buckets.get access" without it.
# bucketViewer adds only buckets.get and buckets.list: no write, no delete.
echo "Granting IAM..."
for role in roles/storage.objectViewer roles/storage.bucketViewer; do
  grant_with_retry gcloud storage buckets add-iam-policy-binding "gs://${SOURCE_BUCKET}" \
    --member="serviceAccount:${SA_EMAIL}" --role="$role" \
    --project="$SOURCE_PROJECT"
done

# On the destination: objectAdmin, which includes delete.
#
# This used to be objectCreator, on the assumption that create-without-delete
# still allowed overwrites because versioning turns them into archiving. That
# assumption is wrong, and it silently broke the backups: overwriting an
# existing GCS object requires storage.objects.delete regardless of versioning.
# The job would copy new files happily and fail with 403 on every file that had
# changed since it was first copied -- so a budget was backed up once and never
# refreshed, while the job kept reporting the same failure nobody watched.
#
# What objectCreator was protecting against is already covered by the bucket
# itself: versioning archives every overwrite, and the soft delete policy makes
# even a deliberate purge recoverable for seven days.
for role in roles/storage.objectViewer roles/storage.bucketViewer roles/storage.objectAdmin; do
  grant_with_retry gcloud storage buckets add-iam-policy-binding "gs://${DEST_BUCKET}" \
    --member="serviceAccount:${SA_EMAIL}" --role="$role" \
    --project="$BACKUP_PROJECT"
done

# --- Cloud Run Job ------------------------------------------------------------
# No --delete-unmatched-destination-objects: a file removed from the source
# stays in the backup. That is the point of a backup.
#
# --checksums-only compares object hashes instead of modification times. The
# source is written by gcsfuse, which records its own gcsfuse_mtime rather than
# the goog-reserved-file-mtime that rsync reads, so mtime comparison rests on
# metadata that is not reliably there. Hashes are already in GCS metadata, so
# this costs no transfer.
JOB_VERB=create
gcloud run jobs describe "$JOB_NAME" --region="$REGION" \
  --project="$BACKUP_PROJECT" >/dev/null 2>&1 && JOB_VERB=update

gcloud run jobs "$JOB_VERB" "$JOB_NAME" \
  --image="$IMAGE" \
  --command=gcloud \
  --args="storage,rsync,--recursive,--checksums-only,gs://${SOURCE_BUCKET},gs://${DEST_BUCKET}" \
  --service-account="$SA_EMAIL" \
  --max-retries=2 \
  --task-timeout=900s \
  --memory=512Mi \
  --region="$REGION" \
  --project="$BACKUP_PROJECT"

# --- Cloud Scheduler ----------------------------------------------------------
# Scoped to this job only, never roles/run.invoker at project level.
grant_with_retry gcloud run jobs add-iam-policy-binding "$JOB_NAME" \
  --member="serviceAccount:${SCHEDULER_SA_EMAIL}" --role=roles/run.invoker \
  --region="$REGION" --project="$BACKUP_PROJECT"

SCHED_VERB=create
gcloud scheduler jobs describe "${JOB_NAME}-daily" --location="$REGION" \
  --project="$BACKUP_PROJECT" >/dev/null 2>&1 && SCHED_VERB=update

gcloud scheduler jobs "$SCHED_VERB" http "${JOB_NAME}-daily" \
  --location="$REGION" \
  --schedule="$SCHEDULE" \
  --time-zone="$TIMEZONE" \
  --uri="https://run.googleapis.com/v2/projects/${BACKUP_PROJECT}/locations/${REGION}/jobs/${JOB_NAME}:run" \
  --http-method=POST \
  --oauth-service-account-email="$SCHEDULER_SA_EMAIL" \
  --project="$BACKUP_PROJECT"

echo ""
echo "Backup configured."
echo "  gs://${SOURCE_BUCKET}  ->  gs://${DEST_BUCKET}"
echo ""
echo "Run it now:      gcloud run jobs execute ${JOB_NAME} --region=${REGION} --project=${BACKUP_PROJECT}"
echo "Change schedule: gcloud scheduler jobs update http ${JOB_NAME}-daily --schedule='0 6 * * *' --location=${REGION} --project=${BACKUP_PROJECT}"
