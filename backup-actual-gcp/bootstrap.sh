#!/usr/bin/env bash
set -euo pipefail

# One-time setup of the central backup project.
#
#   ./bootstrap.sh <backup-project-id>
#
# Run this once, then use add-instance.sh per Actual instance.

BACKUP_PROJECT="${1:-${BACKUP_PROJECT:-}}"
REGION="${REGION:-europe-west9}"
BILLING_ACCOUNT="${BILLING_ACCOUNT:-$(gcloud billing accounts list \
  --filter='open=true' --format='value(name)' --limit=1 2>/dev/null)}"

SCHEDULER_SA="backup-scheduler-sa"
SCHEDULER_SA_EMAIL="${SCHEDULER_SA}@${BACKUP_PROJECT}.iam.gserviceaccount.com"

if [[ -z "$BACKUP_PROJECT" ]]; then
  echo "usage: $0 <backup-project-id>" >&2
  echo "  env: REGION BILLING_ACCOUNT" >&2
  exit 1
fi

if [[ -z "$BILLING_ACCOUNT" ]]; then
  echo "error: no open billing account found." >&2
  echo "  gcloud billing accounts list" >&2
  exit 1
fi

# Project IDs are globally unique and never reusable, so a plausible name is
# often already taken by a stranger.
if ! gcloud projects describe "$BACKUP_PROJECT" >/dev/null 2>&1; then
  echo "Creating project ${BACKUP_PROJECT}..."
  gcloud projects create "$BACKUP_PROJECT"
fi

if ! gcloud billing projects describe "$BACKUP_PROJECT" \
     --format='value(billingEnabled)' 2>/dev/null | grep -qi true; then
  gcloud billing projects link "$BACKUP_PROJECT" --billing-account="$BILLING_ACCOUNT"
fi

gcloud services enable \
  run.googleapis.com \
  storage.googleapis.com \
  cloudscheduler.googleapis.com \
  iam.googleapis.com \
  --project="$BACKUP_PROJECT"

# Cloud Scheduler calls the Cloud Run Jobs API as this account. It is granted
# roles/run.invoker per job by add-instance.sh, never at project level.
if ! gcloud iam service-accounts describe "$SCHEDULER_SA_EMAIL" \
     --project="$BACKUP_PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SCHEDULER_SA" \
    --display-name="Cloud Scheduler -> Cloud Run Jobs invoker" \
    --project="$BACKUP_PROJECT"
fi

echo ""
echo "Backup project ready: ${BACKUP_PROJECT} (${REGION})"
echo "Scheduler SA:         ${SCHEDULER_SA_EMAIL}"
echo ""
echo "Next: ./add-instance.sh <source-project> ${BACKUP_PROJECT}"
