#!/usr/bin/env bash
set -euo pipefail

# Deploy a FreshRSS instance on Cloud Run, with its data on a Cloud Storage
# bucket and its feeds refreshed by Cloud Scheduler.
#
#   ./deploy.sh my-project
#
# Idempotent: running it again reuses the bucket, the service account, the
# secrets and the budget, and only redeploys the service and the refresh job.
# It is therefore also the update procedure.

PROJECT_ID="${1:-${PROJECT_ID:-}}"
REGION="${REGION:-europe-west9}"
# Defaults to your first open billing account. Set it explicitly if you have
# more than one, or the wrong one will get charged.
#
# The `|| true` is load-bearing. Not being able to list billing accounts is a
# normal outcome -- the Cloud Billing API may be off, or the identity may have
# no billing permissions -- but under `set -e` the failing substitution aborts
# the whole script, and `2>/dev/null` means it does so with no output at all.
BILLING_ACCOUNT="${BILLING_ACCOUNT:-$(gcloud billing accounts list \
  --filter='open=true' --format='value(name)' --limit=1 2>/dev/null || true)}"
FRESHRSS_VERSION="${FRESHRSS_VERSION:-}"
ADMIN_USER="${ADMIN_USER:-admin}"
LANGUAGE="${LANGUAGE:-fr}"
TIMEZONE="${TIMEZONE:-Europe/Paris}"
REFRESH_SCHEDULE="${REFRESH_SCHEDULE:-0 * * * *}"
BUDGET_AMOUNT="${BUDGET_AMOUNT:-5}"

SERVICE_NAME="freshrss"
SA_NAME="freshrss-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
JOB_NAME="freshrss-refresh"
JOB_SA_NAME="freshrss-refresh-sa"
JOB_SA_EMAIL="${JOB_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
PW_SECRET="freshrss-admin-password"
TOKEN_SECRET="freshrss-refresh-token"
# Small, purpose-built image: the refresh job runs hourly and is billed for the
# time it takes to start, so a 1 GB toolbox image would cost real money here.
# (The 512Mi floor below is not ours to choose: Cloud Run Jobs run gen2 with CPU
# always allocated, which refuses anything smaller.)
CURL_IMAGE="curlimages/curl:8.11.1"
BUDGET_NAME="Budget ${PROJECT_ID}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "usage: $0 <project-id>" >&2
  echo "  env: REGION FRESHRSS_VERSION ADMIN_USER LANGUAGE TIMEZONE" >&2
  echo "       REFRESH_SCHEDULE BUDGET_AMOUNT BILLING_ACCOUNT" >&2
  exit 1
fi

# Not knowing the billing account is only fatal when the project still has to
# be created or linked. On an already-billed project it costs the budget alert
# and nothing else -- which matters when running under a service account that
# deliberately has no billing permissions, where `billing accounts list`
# returns empty rather than failing.
PROJECT_EXISTS=false
gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1 && PROJECT_EXISTS=true

# Billing state is only knowable when the Cloud Billing API is enabled on the
# project AND the identity may read it. Neither holds for a deployment service
# account by default, so treat "unknown" as its own state: conflating it with
# "not billed" would block a deployment on an existing, obviously-billed
# project -- one already running services -- over information it never needs.
BILLING_STATE=unknown
if [[ "$PROJECT_EXISTS" == true ]]; then
  if billing_out="$(gcloud billing projects describe "$PROJECT_ID" \
       --format='value(billingEnabled)' 2>/dev/null)"; then
    if grep -qi true <<<"$billing_out"; then
      BILLING_STATE=billed
    else
      BILLING_STATE=unbilled
    fi
  fi
fi

# Only creating the project genuinely requires a billing account.
if [[ "$PROJECT_EXISTS" != true && -z "$BILLING_ACCOUNT" ]]; then
  echo "error: ${PROJECT_ID} does not exist and no billing account is known." >&2
  echo "  gcloud billing accounts list" >&2
  echo "  BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX $0 $PROJECT_ID" >&2
  exit 1
fi

if [[ "$BILLING_STATE" == unbilled && -z "$BILLING_ACCOUNT" ]]; then
  echo "error: ${PROJECT_ID} exists but has no billing account linked." >&2
  echo "  BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX $0 $PROJECT_ID" >&2
  exit 1
fi

# The install arguments are word-split by the container entrypoint, so a value
# containing a space would silently become two arguments.
if [[ "$ADMIN_USER" == *[[:space:]]* ]]; then
  echo "error: ADMIN_USER must not contain whitespace." >&2
  exit 1
fi

if [[ -z "$FRESHRSS_VERSION" ]]; then
  # Same trap as above: an unreachable or rate-limited GitHub API makes this
  # pipeline fail, and under `set -o pipefail` that would abort the script
  # instead of reaching the actionable error message below.
  FRESHRSS_VERSION="$(curl -fsSL https://api.github.com/repos/FreshRSS/FreshRSS/releases/latest 2>/dev/null \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1 || true)"
  if [[ -z "$FRESHRSS_VERSION" ]]; then
    echo "error: could not resolve the latest FreshRSS version." >&2
    echo "  set it explicitly: FRESHRSS_VERSION=1.29.0 $0 $PROJECT_ID" >&2
    exit 1
  fi
fi

echo "Project:  ${PROJECT_ID}"
echo "Region:   ${REGION}"
echo "Version:  ${FRESHRSS_VERSION}"
echo "Refresh:  ${REFRESH_SCHEDULE} (${TIMEZONE})"
echo ""

# --- Project -----------------------------------------------------------------

if [[ "$PROJECT_EXISTS" != true ]]; then
  echo "Creating project ${PROJECT_ID}..."
  gcloud projects create "$PROJECT_ID"
fi

if [[ "$BILLING_STATE" == unbilled ]]; then
  echo "Linking billing account ${BILLING_ACCOUNT}..."
  gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
fi

gcloud services enable \
  run.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  secretmanager.googleapis.com \
  cloudscheduler.googleapis.com \
  billingbudgets.googleapis.com \
  --project="$PROJECT_ID"

# --- Bucket ------------------------------------------------------------------
# uniform-bucket-level-access: IAM is the only access path, no per-object ACLs.
# public-access-prevention: the bucket can never be granted to allUsers.
# Versioning turns an overwrite into an archive, which is the only safety net
# this service has -- there is deliberately no backup job (see SKILL.md).

BUCKET_NAME="$(gcloud storage buckets list --project="$PROJECT_ID" \
  --format='value(name)' 2>/dev/null | grep '^freshrss-' | head -1 || true)"

if [[ -z "$BUCKET_NAME" ]]; then
  BUCKET_NAME="freshrss-$(openssl rand -hex 4)"
  echo "Creating bucket gs://${BUCKET_NAME}..."
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --project="$PROJECT_ID"
else
  echo "Reusing bucket gs://${BUCKET_NAME}"
fi

gcloud storage buckets update "gs://${BUCKET_NAME}" --versioning --project="$PROJECT_ID"

# --- Service accounts --------------------------------------------------------
# Without --service-account the service runs as the default Compute service
# account. Grant nothing at project level.

for pair in "${SA_NAME}:FreshRSS (Cloud Run)" "${JOB_SA_NAME}:FreshRSS refresh job"; do
  name="${pair%%:*}"
  desc="${pair#*:}"
  if ! gcloud iam service-accounts describe \
       "${name}@${PROJECT_ID}.iam.gserviceaccount.com" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud iam service-accounts create "$name" \
      --display-name="$desc" --project="$PROJECT_ID"
  fi
done

# A freshly created service account is not immediately usable in IAM bindings;
# the binding can be rejected with "Service account ... does not exist" for up
# to a minute. Retry rather than rely on a fixed sleep.
retry_binding() {
  local what="$1"; shift
  for attempt in $(seq 1 12); do
    "$@" >/dev/null 2>&1 && return 0
    if [[ "$attempt" -eq 12 ]]; then
      echo "error: could not grant ${what} after 2 minutes." >&2
      return 1
    fi
    sleep 10
  done
}

echo "Granting bucket access to the service account..."
retry_binding "bucket access" \
  gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role=roles/storage.objectAdmin \
    --project="$PROJECT_ID"

# --- Secrets -----------------------------------------------------------------
# Generated once and never regenerated, so re-running this script does not lock
# you out. Alphanumeric only: both values are expanded through an `eval` in the
# container entrypoint, and a shell metacharacter would break the start-up.

# Note the bounded `head` on the *source*: piping an endless /dev/urandom into
# `head -c 32` kills tr with SIGPIPE, and under `set -o pipefail` that aborts
# the script. Reading a fixed slice first keeps every stage exiting 0.
gen_secret() {
  local value=""
  while [[ "${#value}" -lt 32 ]]; do
    value+="$(head -c 256 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
  done
  printf '%s' "${value:0:32}"
}

ensure_secret() {
  local secret="$1"
  if gcloud secrets describe "$secret" --project="$PROJECT_ID" >/dev/null 2>&1; then
    return 0
  fi
  echo "Creating secret ${secret}..."
  gen_secret | gcloud secrets create "$secret" --project="$PROJECT_ID" \
    --replication-policy=user-managed --locations="$REGION" --data-file=-
}

ensure_secret "$PW_SECRET"
ensure_secret "$TOKEN_SECRET"

echo "Granting secret access..."
# The service needs both to install itself and create the admin user; the
# refresh job needs only the token.
retry_binding "access to ${PW_SECRET}" \
  gcloud secrets add-iam-policy-binding "$PW_SECRET" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role=roles/secretmanager.secretAccessor --project="$PROJECT_ID"
retry_binding "access to ${TOKEN_SECRET}" \
  gcloud secrets add-iam-policy-binding "$TOKEN_SECRET" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role=roles/secretmanager.secretAccessor --project="$PROJECT_ID"
retry_binding "job access to ${TOKEN_SECRET}" \
  gcloud secrets add-iam-policy-binding "$TOKEN_SECRET" \
    --member="serviceAccount:${JOB_SA_EMAIL}" \
    --role=roles/secretmanager.secretAccessor --project="$PROJECT_ID"

# --- Deploy ------------------------------------------------------------------
# The Cloud Run URL is deterministic, so base_url is known before the first
# deployment -- which it has to be, since FreshRSS bakes it into config.php at
# install time.

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
BASE_URL="https://${SERVICE_NAME}-${PROJECT_NUMBER}.${REGION}.run.app"

# FRESHRSS_INSTALL and FRESHRSS_USER are argument lists for cli/do-install.php
# and cli/create-user.php, replayed by the entrypoint on every start. Both are
# no-ops once the instance is installed (exit code 3), so they stay in the spec.
#
# They matter for more than convenience: they close the window during which a
# public, not-yet-installed FreshRSS lets any visitor run the web installer and
# claim the instance.
#
# The entrypoint evaluates these strings, so $ADMIN_PASSWORD and $REFRESH_TOKEN
# are expanded inside the container from the values Secret Manager injects.
# They must stay single-quoted here: nothing secret is in the spec itself.
INSTALL_ARGS="--default-user ${ADMIN_USER} --base-url ${BASE_URL} --auth-type form --api-enabled --language ${LANGUAGE} --title FreshRSS"
USER_ARGS='--user '"${ADMIN_USER}"' --password $ADMIN_PASSWORD --token $REFRESH_TOKEN --language '"${LANGUAGE}"

# 169.254.0.0/16 is Cloud Run's link-local hop. The entrypoint feeds this to
# Apache's RemoteIPInternalProxy *and* it overrides FreshRSS's trusted_sources,
# so without it FreshRSS logs Google's proxy address instead of the client's.
# Whitespace-separated: Apache and the PHP side both split on it.
TRUSTED_PROXY='169.254.0.0/16 127.0.0.0/8 ::1/128'

deploy_service() {
  gcloud run deploy "$SERVICE_NAME" \
    --image="freshrss/freshrss:${FRESHRSS_VERSION}" \
    --allow-unauthenticated \
    --port=80 \
    --service-account="$SA_EMAIL" \
    --cpu=1 \
    --memory=512Mi \
    --min-instances=0 \
    --max-instances=1 \
    --cpu-boost \
    --timeout=900 \
    --execution-environment=gen2 \
    --set-env-vars="^|^TZ=${TIMEZONE}|TRUSTED_PROXY=${TRUSTED_PROXY}|FRESHRSS_INSTALL=${INSTALL_ARGS}|FRESHRSS_USER=${USER_ARGS}" \
    --set-secrets="ADMIN_PASSWORD=${PW_SECRET}:latest,REFRESH_TOKEN=${TOKEN_SECRET}:latest" \
    --add-volume="name=gcs-1,type=cloud-storage,bucket=${BUCKET_NAME}" \
    --add-volume-mount="volume=gcs-1,mount-path=/var/www/FreshRSS/data" \
    --region="$REGION" \
    --project="$PROJECT_ID"
}

# Even once the binding exists, the metadata server can still fail to mint a
# token for the new service account. That surfaces as a gcsfuse mount failure
# ("cannot fetch token: ... Received 500") and the revision never starts.
# Deploying again is safe: a revision that fails to start receives no traffic.
for attempt in 1 2 3; do
  deploy_service && break

  if [[ "$attempt" -eq 3 ]]; then
    echo "error: the deployment failed three times." >&2
    echo "  check the logs: gcloud run services logs read ${SERVICE_NAME} --project=${PROJECT_ID} --region=${REGION}" >&2
    exit 1
  fi
  echo "Deployment failed. This is usually IAM propagation, retrying in 60s..."
  sleep 60
done

# --- Feed refresh ------------------------------------------------------------
# FreshRSS's built-in cron (CRON_MIN) is a crontab *inside the container*: it
# only fires while the container is awake, which at min-instances=0 is never.
# So the trigger has to come from outside.
#
# The token is not passed in the Scheduler URI on purpose. A Scheduler target
# URL is readable by anyone with cloudscheduler.viewer and is written to Cloud
# Logging on every run -- and this token is not merely a refresh trigger: it
# also serves the RSS output and the OPML subscription list. It stays in Secret
# Manager, and a tiny Cloud Run Job reads it at runtime.

JOB_VERB=create
gcloud run jobs describe "$JOB_NAME" --region="$REGION" \
  --project="$PROJECT_ID" >/dev/null 2>&1 && JOB_VERB=update

# -G turns the --data-urlencode pairs into a query string, so the token is
# escaped rather than concatenated by hand.
gcloud run jobs "$JOB_VERB" "$JOB_NAME" \
  --image="$CURL_IMAGE" \
  --service-account="$JOB_SA_EMAIL" \
  --set-env-vars="BASE_URL=${BASE_URL},FRESHRSS_USER_NAME=${ADMIN_USER}" \
  --set-secrets="REFRESH_TOKEN=${TOKEN_SECRET}:latest" \
  --max-retries=1 \
  --task-timeout=900s \
  --memory=512Mi \
  --command=sh \
  --args='^|^-c|curl -fsS --max-time 840 -G "$BASE_URL/i/" --data-urlencode c=feed --data-urlencode a=actualize --data-urlencode user="$FRESHRSS_USER_NAME" --data-urlencode token="$REFRESH_TOKEN" -o /dev/null' \
  --region="$REGION" \
  --project="$PROJECT_ID"

# Scoped to this job only, never roles/run.invoker at project level.
retry_binding "run.invoker on ${JOB_NAME}" \
  gcloud run jobs add-iam-policy-binding "$JOB_NAME" \
    --member="serviceAccount:${JOB_SA_EMAIL}" \
    --role=roles/run.invoker \
    --region="$REGION" --project="$PROJECT_ID"

SCHED_VERB=create
gcloud scheduler jobs describe "${JOB_NAME}-hourly" --location="$REGION" \
  --project="$PROJECT_ID" >/dev/null 2>&1 && SCHED_VERB=update

gcloud scheduler jobs "$SCHED_VERB" http "${JOB_NAME}-hourly" \
  --location="$REGION" \
  --schedule="$REFRESH_SCHEDULE" \
  --time-zone="$TIMEZONE" \
  --uri="https://run.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/jobs/${JOB_NAME}:run" \
  --http-method=POST \
  --oauth-service-account-email="$JOB_SA_EMAIL" \
  --project="$PROJECT_ID"

# --- Budget alert ------------------------------------------------------------
# Scoped to this project, so a runaway bill is attributable to one service.
# Non-fatal: the deployment already succeeded by this point.

create_budget() {
  local token
  token="$(gcloud auth print-access-token)"

  if curl -fsSL -H "Authorization: Bearer ${token}" \
       -H "x-goog-user-project: ${PROJECT_ID}" \
       "https://billingbudgets.googleapis.com/v1/billingAccounts/${BILLING_ACCOUNT}/budgets" \
     | grep -q "\"displayName\": \"${BUDGET_NAME}\""; then
    echo "Budget alert already exists."
    return 0
  fi

  curl -fsSL -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    -H "Content-Type: application/json" \
    "https://billingbudgets.googleapis.com/v1/billingAccounts/${BILLING_ACCOUNT}/budgets" \
    -d "{
      \"displayName\": \"${BUDGET_NAME}\",
      \"budgetFilter\": {
        \"projects\": [\"projects/${PROJECT_NUMBER}\"],
        \"calendarPeriod\": \"MONTH\",
        \"creditTypesTreatment\": \"INCLUDE_ALL_CREDITS\"
      },
      \"amount\": {
        \"specifiedAmount\": {\"currencyCode\": \"EUR\", \"units\": \"${BUDGET_AMOUNT}\"}
      },
      \"thresholdRules\": [
        {\"thresholdPercent\": 0.5},
        {\"thresholdPercent\": 0.9},
        {\"thresholdPercent\": 1.0},
        {\"thresholdPercent\": 1.0, \"spendBasis\": \"FORECASTED_SPEND\"}
      ]
    }" >/dev/null
  echo "Budget alert created at ${BUDGET_AMOUNT} EUR/month."
}

if [[ -z "$BILLING_ACCOUNT" ]]; then
  echo "note: no billing account known, skipping the budget alert. Create it" >&2
  echo "  later with BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX $0 $PROJECT_ID" >&2
elif ! create_budget; then
  echo "warning: could not create the budget alert (the API may still be" >&2
  echo "  activating, or this identity has no billing permissions). Retry" >&2
  echo "  later, or create it in the console." >&2
fi

# --- Done --------------------------------------------------------------------

echo ""
echo "FreshRSS ${FRESHRSS_VERSION} deployed:"
echo "$BASE_URL"
echo ""
echo "Bucket:           gs://${BUCKET_NAME}"
echo "Service account:  ${SA_EMAIL}"
echo "Refresh:          ${JOB_NAME}, ${REFRESH_SCHEDULE} (${TIMEZONE})"
echo ""
echo "Log in as '${ADMIN_USER}'. The password was generated, never displayed,"
echo "and lives only in Secret Manager:"
echo "  gcloud secrets versions access latest --secret=${PW_SECRET} --project=${PROJECT_ID}"
echo ""
echo "Check the first refresh actually ran:"
echo "  gcloud run jobs execute ${JOB_NAME} --region=${REGION} --project=${PROJECT_ID} --wait"
