#!/usr/bin/env bash
set -euo pipefail

# Deploy a fresh Actual Budget instance into its own GCP project.
#
#   ./deploy.sh services-prenom-x
#
# Idempotent: running it again against an existing project reuses the bucket,
# the service account and the budget, and only redeploys the service.

PROJECT_ID="${1:-${PROJECT_ID:-}}"
REGION="${REGION:-europe-west9}"
# Defaults to your first open billing account. Set it explicitly if you have
# more than one, or the wrong one will get charged.
BILLING_ACCOUNT="${BILLING_ACCOUNT:-$(gcloud billing accounts list \
  --filter='open=true' --format='value(name)' --limit=1 2>/dev/null)}"
SERVER_VERSION="${SERVER_VERSION:-}"
BUDGET_AMOUNT="${BUDGET_AMOUNT:-5}"

SERVICE_NAME="actual-server"
SA_NAME="actual-server-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUDGET_NAME="Budget ${PROJECT_ID}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "usage: $0 <project-id>" >&2
  echo "  env: REGION SERVER_VERSION BUDGET_AMOUNT BILLING_ACCOUNT" >&2
  exit 1
fi

if [[ -z "$BILLING_ACCOUNT" ]]; then
  echo "error: no open billing account found." >&2
  echo "  gcloud billing accounts list" >&2
  echo "  BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX $0 $PROJECT_ID" >&2
  exit 1
fi

# Actual releases monthly. Resolve the latest tag unless one was pinned.
if [[ -z "$SERVER_VERSION" ]]; then
  SERVER_VERSION="$(curl -fsSL https://api.github.com/repos/actualbudget/actual/releases/latest \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
  if [[ -z "$SERVER_VERSION" ]]; then
    echo "error: could not resolve the latest Actual version." >&2
    echo "  set it explicitly: SERVER_VERSION=26.7.0 $0 $PROJECT_ID" >&2
    exit 1
  fi
fi

echo "Project:  ${PROJECT_ID}"
echo "Region:   ${REGION}"
echo "Version:  ${SERVER_VERSION}"
echo ""

# --- Project -----------------------------------------------------------------

if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  echo "Creating project ${PROJECT_ID}..."
  gcloud projects create "$PROJECT_ID"
fi

if ! gcloud billing projects describe "$PROJECT_ID" \
     --format='value(billingEnabled)' 2>/dev/null | grep -qi true; then
  echo "Linking billing account ${BILLING_ACCOUNT}..."
  gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
fi

gcloud services enable \
  run.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  billingbudgets.googleapis.com \
  --project="$PROJECT_ID"

# --- Bucket ------------------------------------------------------------------
# uniform-bucket-level-access: IAM is the only access path, no per-object ACLs.
# public-access-prevention: the bucket can never be granted to allUsers.
# The budget database lives here, so both are worth having.

BUCKET_NAME="$(gcloud storage buckets list --project="$PROJECT_ID" \
  --format='value(name)' 2>/dev/null | grep '^actual-server-' | head -1 || true)"

if [[ -z "$BUCKET_NAME" ]]; then
  BUCKET_NAME="actual-server-$(openssl rand -hex 4)"
  echo "Creating bucket gs://${BUCKET_NAME}..."
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --project="$PROJECT_ID"
else
  echo "Reusing bucket gs://${BUCKET_NAME}"
fi

# --- Service account ---------------------------------------------------------
# Without --service-account the service runs as the default Compute service
# account. Grant nothing at project level: objectAdmin on this bucket only.

if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Actual Server Service Account" \
    --project="$PROJECT_ID"
fi

# A freshly created service account is not immediately usable in IAM bindings;
# the binding can be rejected with "Service account ... does not exist" for up
# to a minute. Retry rather than rely on a fixed sleep.
echo "Granting bucket access to the service account..."
for attempt in $(seq 1 12); do
  gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role=roles/storage.objectAdmin \
    --project="$PROJECT_ID" >/dev/null 2>&1 && break

  if [[ "$attempt" -eq 12 ]]; then
    echo "error: could not grant bucket access after 2 minutes." >&2
    exit 1
  fi
  sleep 10
done

# --- Deploy ------------------------------------------------------------------
# max-instances=1 is mandatory: SQLite over gcsfuse cannot take two writers.
# The trusted proxies make express-rate-limit key on the real client IP.
# 169.254.0.0/16 is Cloud Run's link-local hop; Express walks X-Forwarded-For
# right to left, so trusting exactly one hop cannot be spoofed.
# ACTUAL_TRUSTED_AUTH_PROXIES inherits from it unless pinned, and it enables
# header-based auth, so it stays at loopback only.

deploy_server() {
  gcloud run deploy "$SERVICE_NAME" \
    --image="actualbudget/actual-server:${SERVER_VERSION}" \
    --allow-unauthenticated \
    --port=5006 \
    --service-account="$SA_EMAIL" \
    --cpu=1 \
    --memory=512Mi \
    --min-instances=0 \
    --max-instances=1 \
    --cpu-boost \
    --execution-environment=gen2 \
    --set-env-vars="^|^ACTUAL_TRUSTED_PROXIES=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,fc00::/7,::1/128,169.254.0.0/16|ACTUAL_TRUSTED_AUTH_PROXIES=::1/128" \
    --add-volume="name=gcs-1,type=cloud-storage,bucket=${BUCKET_NAME}" \
    --add-volume-mount="volume=gcs-1,mount-path=/data" \
    --region="$REGION" \
    --project="$PROJECT_ID"
}

# Even once the binding exists, the metadata server can still fail to mint a
# token for the new service account. That surfaces as a gcsfuse mount failure
# ("cannot fetch token: ... Received 500") and the revision never starts.
# Deploying again is safe: a revision that fails to start receives no traffic.
for attempt in 1 2 3; do
  deploy_server && break

  if [[ "$attempt" -eq 3 ]]; then
    echo "error: the deployment failed three times." >&2
    echo "  check the logs: gcloud run services logs read ${SERVICE_NAME} --project=${PROJECT_ID} --region=${REGION}" >&2
    exit 1
  fi
  echo "Deployment failed. This is usually IAM propagation, retrying in 60s..."
  sleep 60
done

# --- Budget alert ------------------------------------------------------------
# Scoped to this project, so a runaway bill is attributable to one service.
# Non-fatal: the deployment already succeeded by this point.

create_budget() {
  local token project_number
  token="$(gcloud auth print-access-token)"
  project_number="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

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
        \"projects\": [\"projects/${project_number}\"],
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

if ! create_budget; then
  echo "warning: could not create the budget alert (the API may still be" >&2
  echo "  activating). Retry later, or create it in the console." >&2
fi

# --- Done --------------------------------------------------------------------

URL="$(gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" --project="$PROJECT_ID" \
  --format='value(status.url)')"

echo ""
echo "Actual Budget ${SERVER_VERSION} deployed:"
echo "$URL"
echo ""
echo "Bucket:           gs://${BUCKET_NAME}"
echo "Service account:  ${SA_EMAIL}"
echo ""
echo "Create the first account now: the service is public until one exists."
