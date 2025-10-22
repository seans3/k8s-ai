#!/bin/bash
#
# This script runs a diagnostic pod in your GKE cluster to verify that
# Workload Identity is correctly configured. It checks if the specified
# Kubernetes Service Account can impersonate the GCP Service Account
# and access the target GCS bucket.

set -e

# --- Configuration ---
# You can set these environment variables before running the script.
# The script will use the values from the README.md as defaults if not set.

: "${GCP_PROJECT_ID:=$(gcloud config get-value project)}"
: "${K8S_NAMESPACE:=default}"
: "${K8S_SERVICE_ACCOUNT:=vllm-sa}"
: "${GCP_SERVICE_ACCOUNT:=vllm-gcs-reader}"
: "${GCS_BUCKET_URI:=gs://ai-llm-models}" # IMPORTANT: Change this to your bucket if it's different

# --- Script Logic ---

# Generate a unique name for the diagnostic pod
POD_NAME="wi-diagnostic-pod-$(date +%s)"

# Construct the full GCP Service Account email
GCP_SA_EMAIL="${GCP_SERVICE_ACCOUNT}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

echo "--- Starting Workload Identity Verification ---"
echo "Project:              ${GCP_PROJECT_ID}"
echo "GCS Bucket:           ${GCS_BUCKET_URI}"
echo "K8s Service Account:  ${K8S_SERVICE_ACCOUNT} in namespace '${K8S_NAMESPACE}'"
echo "GCP Service Account:  ${GCP_SA_EMAIL}"
echo "Diagnostic Pod Name:  ${POD_NAME}"
echo

# Check if the K8s service account exists
if ! kubectl get sa "${K8S_SERVICE_ACCOUNT}" -n "${K8S_NAMESPACE}" > /dev/null; then
  echo "❌ Error: Kubernetes Service Account '${K8S_SERVICE_ACCOUNT}' not found in namespace '${K8S_NAMESPACE}'."
  echo "Please create it first using 'kubectl apply -f ./service-account.yaml'"
  exit 1
fi

echo "🚀 Step 1: Creating diagnostic pod..."
# Create a pod manifest using a 'here document' and apply it.
# This is more robust than using 'kubectl run' with flags that might change.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${K8S_NAMESPACE}
spec:
  serviceAccountName: ${K8S_SERVICE_ACCOUNT}
  containers:
  - name: diag-container
    image: google/cloud-sdk:slim
    command:
    - /bin/sh
    - -c
    # This is the corrected command:
    - "set -e -x; echo 'Verifying Workload Identity by listing bucket...'; gcloud storage ls ${GCS_BUCKET_URI}"
  restartPolicy: Never
EOF

# Cleanup function to ensure the pod is always deleted
cleanup() {
  echo "🧹 Step 4: Cleaning up diagnostic pod..."
  kubectl delete pod "${POD_NAME}" --namespace="${K8S_NAMESPACE}" --ignore-not-found=true
}
# Register the cleanup function to be called on script exit
trap cleanup EXIT

echo "⏳ Step 2: Waiting for pod to complete (timeout in 2 minutes)..."

# Wait for the pod to succeed. If it times out (which can happen with fast-finishing pods),
# we'll manually check its final status.
if ! kubectl wait --for=condition=Succeeded pod/"${POD_NAME}" --namespace="${K8S_NAMESPACE}" --timeout=2m; then
    echo
    echo "⏳ 'kubectl wait' timed out. This is common for short-lived pods."
    echo "Checking the final pod phase..."
    FINAL_PHASE=$(kubectl get pod "${POD_NAME}" -n "${K8S_NAMESPACE}" -o jsonpath='{.status.phase}')

    if [[ "${FINAL_PHASE}" == "Succeeded" ]]; then
        echo "✅ Pod phase is 'Succeeded'. The test was successful."
    else
        echo "❌ Pod phase is '${FINAL_PHASE}'. The test failed."
        echo "Dumping pod description and logs for debugging:"
        kubectl describe pod "${POD_NAME}" --namespace="${K8S_NAMESPACE}"
        echo
        kubectl logs "${POD_NAME}" --namespace="${K8S_NAMESPACE}"
        exit 1
    fi
fi

echo "✅ Pod completed successfully."
echo
echo "📋 Step 3: Fetching logs from the pod..."
echo "-------------------------------------------"
kubectl logs "${POD_NAME}" --namespace="${K8S_NAMESPACE}"
echo "-------------------------------------------"
echo
echo "✅ Success! The diagnostic pod was able to authenticate using Workload Identity and access the GCS bucket."
echo
