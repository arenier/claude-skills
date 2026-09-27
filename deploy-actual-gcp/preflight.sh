#!/usr/bin/env bash
set -uo pipefail

# Check everything deploy.sh needs before it runs, without changing anything.
#
#   ./preflight.sh <project-id>
#
# Reports the active account, whether the project ID is valid and follows the
# naming convention, whether the project already exists (then deploy.sh is an
# update) and which billing accounts are open. Ends with PREFLIGHT=ok or
# PREFLIGHT=blocked; exits 1 when blocked.

PROJECT_ID="${1:-}"
REGION="${REGION:-europe-west9}"
SERVICE_NAME="actual-server"

if [[ -z "$PROJECT_ID" ]]; then
  echo "usage: $0 <project-id>" >&2
  exit 2
fi

blocking=()
ok()   { echo "OK  $*"; }
note() { echo "!!  $*"; }
ko()   { echo "KO  $*"; blocking+=("$*"); }

if ! command -v gcloud >/dev/null 2>&1; then
  ko "gcloud is not installed"
  echo "PREFLIGHT=blocked"
  exit 1
fi

ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)"
if [[ -n "$ACCOUNT" ]]; then
  ok "active account: ${ACCOUNT}"
else
  ko "no active account: the user must run \`! gcloud auth login\` (interactive)"
fi

# Project IDs: 6-30 characters, lowercase letters, digits and hyphens, starting
# with a letter and not ending with a hyphen.
if [[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
  ok "valid project ID: ${PROJECT_ID}"
else
  ko "invalid project ID: ${PROJECT_ID} (6-30 chars, a-z 0-9 -, starts with a letter)"
fi
if [[ ! "$PROJECT_ID" =~ ^services-[a-z]+-[a-z]$ ]]; then
  note "outside the services-<firstname>-<initial> convention"
fi

PROJECT_EXISTS=false
if (( ${#blocking[@]} > 0 )); then
  :  # no account or invalid ID: nothing more to learn about the project
elif gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  PROJECT_EXISTS=true
  ok "project exists and is accessible: deploy.sh will update it"
  image="$(gcloud run services describe "$SERVICE_NAME" --region="$REGION" --project="$PROJECT_ID" \
    --format='value(spec.template.spec.containers[0].image)' 2>/dev/null)"
  if [[ -n "$image" ]]; then
    note "Actual already deployed here (${image}): this run is an update"
  fi
else
  note "project not found or not accessible: deploy.sh will create it, and fail if a stranger already owns the ID (IDs are global and never reused)"
fi

BILLING="$(gcloud billing accounts list --filter='open=true' --format='value(name,displayName)' 2>/dev/null || true)"
count="$(grep -c . <<<"$BILLING" || true)"
if [[ "$count" -eq 0 ]]; then
  if [[ "$PROJECT_EXISTS" == true ]]; then
    note "no open billing account visible: fine if the project is already billed, but no budget alert"
  else
    ko "no open billing account: the project cannot be created"
  fi
elif [[ "$count" -eq 1 ]]; then
  ok "billing account: ${BILLING}"
elif [[ -z "${BILLING_ACCOUNT:-}" ]]; then
  note "${count} open billing accounts, deploy.sh would take the first one. Choose and set BILLING_ACCOUNT:"
  while IFS= read -r line; do echo "      ${line}"; done <<<"$BILLING"
else
  ok "billing account pinned: ${BILLING_ACCOUNT}"
fi

if (( ${#blocking[@]} > 0 )); then
  echo "PREFLIGHT=blocked"
  exit 1
fi
echo "PREFLIGHT=ok"
