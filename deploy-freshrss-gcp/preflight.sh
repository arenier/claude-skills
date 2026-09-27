#!/usr/bin/env bash
set -uo pipefail

# Check everything deploy.sh needs before it runs, without changing anything.
#
#   ./preflight.sh <project-id>
#
# Reports the active account, whether the project exists (then deploy.sh is an
# update, or an addition to a project already running other services), its
# billing state, and the open billing accounts. Ends with PREFLIGHT=ok or
# PREFLIGHT=blocked; exits 1 when blocked.

PROJECT_ID="${1:-}"
REGION="${REGION:-europe-west9}"
SERVICE_NAME="freshrss"

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

if [[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
  ok "valid project ID: ${PROJECT_ID}"
else
  ko "invalid project ID: ${PROJECT_ID} (6-30 chars, a-z 0-9 -, starts with a letter)"
fi

PROJECT_EXISTS=false
if (( ${#blocking[@]} > 0 )); then
  :  # no account or invalid ID: nothing more to learn about the project
elif gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  PROJECT_EXISTS=true
  ok "project exists and is accessible"
  services="$(gcloud run services list --region="$REGION" --project="$PROJECT_ID" \
    --format='value(metadata.name)' 2>/dev/null | tr '\n' ' ')"
  if [[ " $services " == *" ${SERVICE_NAME} "* ]]; then
    note "FreshRSS already deployed here: this run is an update"
  elif [[ -n "${services// /}" ]]; then
    note "project already runs: ${services}-- FreshRSS will sit alongside"
  fi
  billed="$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled)' 2>/dev/null || true)"
  case "${billed,,}" in
    true)  ok "project is billed" ;;
    false) note "project has no billing account linked: set BILLING_ACCOUNT" ;;
    *)     note "billing state unreadable with this identity: deploy.sh will not block on it" ;;
  esac
else
  note "project not found or not accessible: deploy.sh will create it, and fail if a stranger already owns the ID"
fi

BILLING="$(gcloud billing accounts list --filter='open=true' --format='value(name,displayName)' 2>/dev/null || true)"
count="$(grep -c . <<<"$BILLING" || true)"
if [[ "$count" -eq 0 ]]; then
  if [[ "$PROJECT_EXISTS" == true ]]; then
    note "no open billing account visible: no budget alert will be created"
  elif (( ${#blocking[@]} == 0 )); then
    ko "no open billing account: the project cannot be created"
  fi
elif [[ "$count" -gt 1 && -z "${BILLING_ACCOUNT:-}" ]]; then
  note "${count} open billing accounts, deploy.sh would take the first one. Choose and set BILLING_ACCOUNT:"
  while IFS= read -r line; do echo "      ${line}"; done <<<"$BILLING"
else
  ok "billing account: ${BILLING_ACCOUNT:-$BILLING}"
fi

if (( ${#blocking[@]} > 0 )); then
  echo "PREFLIGHT=blocked"
  exit 1
fi
echo "PREFLIGHT=ok"
