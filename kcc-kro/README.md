# Setting up Admin Cluster

## 1. Tool Installation & Configuration
   
#### gcloud
Install and initialize the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install).

#### kubectl
Install the Kubernetes command-line tool, `kubectl`. The `gcloud` CLI can often install this for you:

```bash
gcloud components install kubectl
```

#### helm
Please install Helm 3.x cli

## 2. Google Cloud Project Setup:

Creating a new Google Cloud (GCP) project. We suggested that you use a separate project to avoid disrupting any production clusters or services. You may choose to follow your own best practices in setting up the project.

Steps to setup a new GCP project: 

```bash
# in *nix shell USER should be set. if not set USERNAME explicitly
export USERNAME=${USER?}
export PROJECT_ID=k8sai-${USERNAME?} 
export REGION=us-central1 # << CHANGE region here 
# Please set the appropriate folder, billing
export GCP_FOLDER=0000000000
export GCP_BILLING=000000-000000-000000
export ADMINUSER=someone@company.com

# Separate Gcloud configuration
gcloud config configurations create k8sai
gcloud config configurations activate k8sai
gcloud config set account ${ADMINUSER?}

# Create the project
gcloud projects create ${PROJECT_ID?} --folder=${GCP_FOLDER?}
gcloud auth application-default set-quota-project ${PROJECT_ID?}

# attach billing (THIS IS IMPORTANT)
gcloud beta billing projects link ${PROJECT_ID?} --billing-account ${GCP_BILLING?}

# Set the project ID in the current configuration
gcloud config set project ${PROJECT_ID?}

# set appropriate region
gcloud config set compute/region us-central1

```

The region is set to `us-central1` as it generally offers good availability of various GPU and TPU resources. However, you should always verify the [Google Cloud documentation for regional availability](https://cloud.google.com/compute/docs/gpus/gpu-regions-zones) of specific accelerators if you have particular hardware needs or for the latest information.

### IAM Permissions
    
Ensure your user account has the necessary IAM (Identity and Access Management) roles for creating and managing GKE clusters and related resources. This might include roles like "Kubernetes Engine Admin" and "Service Account User," or more granular permissions depending on your organization's policies.

## 3. Enable Google Cloud services

Enable the following required APIs:

```
gcloud services enable \
  container.googleapis.com  \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com
```

## 4. GKE Cluster with KCC and KRO

### Create GKE Cluster

```bash
export CLUSTER_NAME="kcc-kro" # name for the admin cluster
export CHANNEL="rapid" # or "regular"

## Create a cluster with kcc addon
gcloud container clusters create ${CLUSTER_NAME} \
    --release-channel ${CHANNEL} \
    --addons ConfigConnector \
    --workload-pool=${PROJECT_ID}.svc.id.goog \
    --logging=SYSTEM \
    --monitoring=SYSTEM
```

Setup Kubectl to target the cluster

```bash
gcloud container clusters get-credentials kro --region $REGION --project $PROJECT_ID
```

### Setup KCC 

Create SA and bind with KCC KSA

```bash
# Instructions from here: https://cloud.google.com/config-connector/docs/how-to/install-manually#identity

# Create KCC operator KSA
gcloud iam service-accounts create kcc-operator

# Add GCP iam role bindings and use WI bind with KSA

## project owner role
gcloud projects add-iam-policy-binding ${PROJECT_ID}\
    --member="serviceAccount:kcc-operator@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/owner"

gcloud iam service-accounts add-iam-policy-binding kcc-operator@${PROJECT_ID}.iam.gserviceaccount.com \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[cnrm-system/cnrm-controller-manager]" \
    --role="roles/iam.workloadIdentityUser"

## storage admin role
gcloud projects add-iam-policy-binding ${PROJECT_ID}\
    --member="serviceAccount:kcc-operator@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.admin"
```

Create the `ConfigConnector` object that sets up the KCC controller

```bash
# from here: https://cloud.google.com/config-connector/docs/how-to/install-manually#addon-configuring

kubectl apply -f - <<EOF
apiVersion: core.cnrm.cloud.google.com/v1beta1
kind: ConfigConnector
metadata:
  name: configconnector.core.cnrm.cloud.google.com
spec:
  mode: cluster
  googleServiceAccount: "kcc-operator@${PROJECT_ID?}.iam.gserviceaccount.com"
  stateIntoSpec: Absent
EOF
```

Create a namespace for KCC resources
```bash
# from here: https://cloud.google.com/config-connector/docs/how-to/install-manually#specify
kubectl create namespace config-connector
kubectl annotate namespace config-connector cnrm.cloud.google.com/project-id=${PROJECT_ID?}
```

Verify KCC Installation
```bash
kubectl wait -n cnrm-system --for=condition=Ready pod --all
```

### Install KRO

Install KRO following [instructions here](https://kro.run/docs/getting-started/Installation/)

```bash
export KRO_VERSION=$(curl -sL \
    https://api.github.com/repos/kro-run/kro/releases/latest | \
    jq -r '.tag_name | ltrimstr("v")'
  )
echo $KRO_VERSION

helm install kro oci://ghcr.io/kro-run/kro/kro \
  --namespace kro \
  --create-namespace \
  --version=${KRO_VERSION}

helm -n kro list
```

## 5.  Model Access (e.g., for Gemma from Hugging Face)

* **Sign License Agreement:** Many models, such as Gemma, require you to agree to their terms of use. For Gemma, this often involves signing a license consent agreement, for example, via Kaggle. Check the specific requirements for the model you intend to use.
* **Hugging Face Access Token:** To download models from the Hugging Face Hub, you'll need an account and an access token.
    * Create a Hugging Face account if you don't have one.
    * Generate an access token with at least 'Read' permissions. You can find detailed instructions on how to create and manage your tokens on the [Hugging Face documentation](https://huggingface.co/docs/hub/en/security-tokens).
    * Keep this token secure; you will use it to create a Kubernetes secret.

### Set Environment Variables

Set up local environment variables in your terminal session for convenience. This makes it easier to copy and paste commands without modification.

```bash
export HF_TOKEN="your-hugging-face-token" # Your actual Hugging Face token
export MODEL_ID="google/gemma-1b-it" # 1 billion parameter (smallest) model
```

Ensure you replace placeholder values like `your-project-id` with your actual information.
## 6. Cleanup

If you are operating in a dev environment and want to clean it up, follow these steps:

```
# in *nix shell USER should be set. if not set USERNAME explicitly
export USERNAME=${USER?}
export PROJECT_ID=compositions-${USERNAME?}
export REGION=us-west2
export CONFIG_CONTROLLER_NAME=compositions

# Delete the GCP project if you created one for trying out KRO
gcloud projects delete ${PROJECT_ID?}
# Delete gcloud configuration
gcloud config configurations activate <anything other than 'compositions'>
gcloud config configurations delete compositions
# Delete kubectl context
kubectl config  delete-context \
gke_${PROJECT_ID?}_${REGION?}_krmapihost-${CONFIG_CONTROLLER_NAME?}

# Dont forget to switch to another context 
kubectl config  get-contexts
kubectl config  use-context <context name>
```
