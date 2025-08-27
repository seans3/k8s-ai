# Environment Setup Guide

This guide provides detailed, step-by-step instructions for setting up your Google Cloud and Kubernetes environment to run the AI inference workloads described in the `README.md`.

## 1. Tool Installation

Install and configure the following command-line tools.

#### Google Cloud CLI
Install and initialize the [Google Cloud CLI (`gcloud`)](https://cloud.google.com/sdk/docs/install). This is essential for interacting with your Google Cloud project.

#### kubectl
Install the Kubernetes command-line tool, `kubectl`. The `gcloud` CLI can install it for you:
```bash
gcloud components install kubectl
```

#### Helm
Install [Helm](https://helm.sh/docs/intro/install/) (version 3.x or later), which is used to install the KRO operator.

## 2. Google Cloud Project Setup

It is highly recommended to use a new, dedicated Google Cloud project to avoid conflicts with existing resources.

The following script sets up environment variables and creates a new project.

```bash
# Set your GCP username and desired region
export USERNAME=${USER}
export PROJECT_ID="k8sai-${USERNAME}"
export REGION="us-central1" # A region with good GPU/TPU availability

# Set your organization or folder ID and billing account
export GCP_ORG="YOUR_ORG_ID" # Or use GCP_FOLDER="YOUR_FOLDER_ID"
export GCP_BILLING="YOUR_BILLING_ACCOUNT" # e.g., 000000-000000-000000
export ADMINUSER=$(gcloud config get-value account)

# Create a separate gcloud configuration to avoid conflicts
gcloud config configurations create k8sai
gcloud config set account ${ADMINUSER}
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}

# Create the project
# Use --organization or --folder depending on your setup
gcloud projects create ${PROJECT_ID} --organization=${GCP_ORG}
# gcloud projects create ${PROJECT_ID} --folder=${GCP_FOLDER}

# Link the billing account to the new project
gcloud beta billing projects link ${PROJECT_ID} --billing-account ${GCP_BILLING}

# Set the new project for application default credentials
gcloud auth application-default set-quota-project ${PROJECT_ID}

echo "GCP project ${PROJECT_ID} created and configured."
```
> **Note:** The region is set to `us-central1` as it generally offers good availability of various GPU and TPU resources. However, you should always verify the [Google Cloud documentation for regional availability](https://cloud.google.com/compute/docs/gpus/gpu-regions-zones) of specific accelerators.

### IAM Permissions
Ensure your user account has the necessary IAM roles to create and manage GKE clusters and related resources, such as `roles/resourcemanager.projectCreator`, `roles/billing.user`, `roles/compute.admin`, `roles/container.admin`, and `roles/iam.serviceAccountAdmin`.

## 3. Enable Google Cloud APIs

Enable the APIs required for GKE and Config Connector:
```bash
gcloud services enable \
  container.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com
```

## 4. GKE Cluster with KCC and KRO

This section guides you through creating a GKE cluster and installing the necessary operators.

### Create a GKE Autopilot Cluster
```bash
export CLUSTER_NAME="inference-cluster"

gcloud container clusters create-auto ${CLUSTER_NAME} \
    --location=${REGION}
```

### Configure `kubectl`
Point `kubectl` to your new cluster:
```bash
gcloud container clusters get-credentials ${CLUSTER_NAME} --location ${REGION}
```

### Install and Configure Config Connector (KCC)

KCC allows you to manage GCP resources via Kubernetes.

1.  **Download and apply the KCC operator:**
    ```bash
    gcloud storage cp gs://configconnector-operator/latest/release-bundle.tar.gz release-bundle.tar.gz
    tar zxvf release-bundle.tar.gz
    kubectl apply -f operator-system/autopilot-configconnector-operator.yaml
    rm -rf release-bundle.tar.gz operator-system/
    ```

2.  **Wait for the operator to be ready:**
    ```bash
    kubectl wait -n configconnector-operator-system --for=condition=Ready pod --all
    ```

3.  **Create a Google Service Account (GSA) for KCC:**
    ```bash
    gcloud iam service-accounts create kcc-operator

    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:kcc-operator@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/owner"
    ```
    > **Security Note:** For production environments, it is recommended to grant more granular permissions instead of `roles/owner`.

4.  **Bind the GSA to the KCC Kubernetes Service Account (KSA):**
    ```bash
    gcloud iam service-accounts add-iam-policy-binding "kcc-operator@${PROJECT_ID}.iam.gserviceaccount.com" \
        --member="serviceAccount:${PROJECT_ID}.svc.id.goog[cnrm-system/cnrm-controller-manager]" \
        --role="roles/iam.workloadIdentityUser"
    ```

5.  **Create the `ConfigConnector` resource:**
    This configures KCC to use the service account you created.
    ```bash
    kubectl apply -f - <<EOF
    apiVersion: core.cnrm.cloud.google.com/v1beta1
    kind: ConfigConnector
    metadata:
      name: configconnector.core.cnrm.cloud.google.com
    spec:
      mode: cluster
      googleServiceAccount: "kcc-operator@${PROJECT_ID}.iam.gserviceaccount.com"
      stateIntoSpec: Absent
    EOF
    ```

### Create and Annotate a Namespace for KCC Resources
This namespace will be used to create KCC-managed resources.
```bash
export NAMESPACE=config-connector
kubectl create namespace ${NAMESPACE}
kubectl annotate namespace ${NAMESPACE} cnrm.cloud.google.com/project-id=${PROJECT_ID}
```

### Verify KCC Installation
```bash
# Wait for all KCC system pods to be ready
kubectl wait -n cnrm-system --for=condition=Ready pod --all
```

### Install Kubernetes Resource Orchestrator (KRO)

KRO is a controller that lets you define and manage composite resources.

```bash
export KRO_VERSION=$(curl -sL https://api.github.com/repos/kro-run/kro/releases/latest | jq -r '.tag_name | ltrimstr("v")')

helm install kro oci://ghcr.io/kro-run/kro/kro \
  --namespace kro \
  --create-namespace \
  --version=${KRO_VERSION}

# Wait for the KRO pod to be ready
kubectl wait -n kro --for=condition=Ready pod --all
```

## 5. Configure Model Access

To download models, you need to provide credentials for Hugging Face and/or Kaggle.

### Hugging Face Access
1.  **Create a Hugging Face account** and [generate an access token](https://huggingface.co/docs/hub/en/security-tokens) with at least 'Read' permissions.
2.  **Create a Kubernetes secret** with your token:
    ```bash
    export HF_TOKEN="your-hugging-face-token" # Replace with your token
    kubectl create secret generic hf-token \
       --namespace=${NAMESPACE} \
       --from-literal=hf_api_token=$HF_TOKEN
    ```

### Kaggle API Access
1.  **Create a Kaggle account** and accept the license terms for the Gemma model you plan to use.
2.  **Download your `kaggle.json` API token** from your Kaggle account page (under the "API" section).
3.  **Create a Kubernetes secret** from the downloaded file:
    ```bash
    # Ensure kaggle.json is in your current directory
    kubectl create secret generic kaggle-token \
       --namespace=${NAMESPACE} \
       --from-file=kaggle.json
    ```

## 6. Install the Custom Resource Definitions

Finally, install the custom resource group definitions (RGDs) that define the high-level `GemmaOnNvidiaL4Server` and `GemmaOnTPUServer` resources.

```bash
# Install Gemma RGDs
kubectl apply -f rgd/gemma-on-nvidial4-server.yaml
kubectl apply -f rgd/gemma-on-tpu-server.yaml

# Check that their state becomes Active
kubectl get rgd
```

Your environment is now fully set up. You can proceed to the main `README.md` to deploy the inference services.

## 7. Cleanup

To avoid incurring ongoing charges, you can delete the resources you created.

**DANGER:** The following command will permanently delete your Google Cloud project and all resources within it.

```bash
# The PROJECT_ID variable should still be set from the setup steps
gcloud projects delete ${PROJECT_ID} --quiet

# Delete the gcloud configuration
gcloud config configurations activate default
gcloud config configurations delete k8sai

# Delete the kubectl context
kubectl config delete-context \
  "gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}"
```
