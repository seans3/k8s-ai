# Prerequisites

This document outlines the necessary steps to prepare your environment for deploying the Gemma model with JetStream on GKE.

---

## 1. Google Cloud Project Setup

a. **Select or Create a Project**: Ensure you have a Google Cloud project with billing enabled.

b. **Enable APIs**: Enable the following APIs in your project.
```bash
gcloud services enable container.googleapis.com \
    compute.googleapis.com \
    tpu.googleapis.com \
    storage.googleapis.com \
    artifactregistry.googleapis.com \
    iamcredentials.googleapis.com \
    --project=YOUR_PROJECT_ID
```
*   Replace `YOUR_PROJECT_ID` with your actual project ID.

c. **IAM Permissions**: Your user account needs the following IAM roles:
*   `roles/container.admin`
*   `roles/tpu.admin`
*   `roles/iam.serviceAccountAdmin`
*   `roles/resourcemanager.projectIamAdmin`
*   `roles/storage.admin`

d. **TPU Quota**: Verify that your project has sufficient quota for the TPU type you plan to use (e.g., `ct5lp-podslice` for TPU v5e). You can check your quotas in the "IAM & Admin" > "Quotas" section of the Google Cloud Console.

---

## 2. Tool Installation and Configuration

a. **Install and Configure `gcloud`**:
*   Install the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install).
*   Update and initialize the CLI:
    ```bash
    gcloud components update
    gcloud init
    ```
*   Set your default project and region:
    ```bash
    gcloud config set project YOUR_PROJECT_ID
    gcloud config set compute/region us-central1
    ```
    *   **Note**: `us-central1` is a recommended region, but you can choose another that supports the required TPU resources.

b. **Install `kubectl`**:
```bash
gcloud components install kubectl
```

---

## 3. Gemma Model Access

a. **Kaggle Account**: You need a Kaggle account and must accept the Gemma model license and usage policy.

b. **Kaggle API Credentials**:
*   Download your `kaggle.json` API token from your Kaggle account page (under the "API" section).
*   This file contains the username and key you will use for the `KAGGLE_USERNAME` and `KAGGLE_KEY` environment variables.

---

## 4. Environment Variables

Export the following environment variables in your local shell. These variables will be used throughout the deployment process.

```bash
# --- Project and Cluster Configuration ---
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export CLUSTER_NAME="jetstream-gemma-cluster"

# --- Kaggle Credentials ---
export KAGGLE_USERNAME="your_kaggle_username"
export KAGGLE_KEY="your_kaggle_key"

# --- Model and GCS Configuration ---
export MODEL_NAME="gemma-2b-it" # Or gemma-7b-it
export MODEL_GCS_BUCKET_NAME="your-unique-bucket-name-${PROJECT_ID}"
export MODEL_GCS_BUCKET="gs://${MODEL_GCS_BUCKET_NAME}"
export CONVERTED_MODEL_GCS_PATH="${MODEL_GCS_BUCKET}/jetstream_checkpoints/${MODEL_NAME}"
export TOKENIZER_GCS_PATH="${MODEL_GCS_BUCKET}/tokenizers/${MODEL_NAME}"

# --- Workload Identity and Kubernetes ---
export GSA_NAME="jetstream-gsa"
export KSA_NAME="jetstream-ksa"
export K8S_NAMESPACE="default"
```

*   **Important**: Replace the placeholder values with your actual information.

After setting the environment variables, create the GCS bucket:
```bash
gsutil mb -p $PROJECT_ID -l $REGION $MODEL_GCS_BUCKET
```