# Prerequisites for Serving Gemma with JetStream and TPUs on GKE Autopilot

Before you deploy a JetStream inference server for Gemma models on GKE Autopilot with TPUs, ensure you have the following prerequisites in place:

1.  **Google Cloud Project Setup:**
    * **Project:** Select an existing Google Cloud project or create a new one.
    * **Billing:** Ensure that billing is enabled for your project.
    * **APIs:** Enable the following APIs in your project:
        * Kubernetes Engine API
        * Compute Engine API
        * TPU API
        * Cloud Storage API (for storing converted models)
        * Artifact Registry API (if using custom Docker images, though tutorial may use pre-built)
        * IAM Service Account Credentials API (for Workload Identity)
        You can enable them using the Google Cloud Console or `gcloud`:
        ```bash
        gcloud services enable container.googleapis.com compute.googleapis.com tpu.googleapis.com storage.googleapis.com artifactregistry.googleapis.com [iamserviceaccountcredentials.googleapis.com](https://www.google.com/search?q=iamserviceaccountcredentials.googleapis.com) --project=YOUR_PROJECT_ID
        ```
        Replace `YOUR_PROJECT_ID` with your actual project ID.

2.  **IAM Permissions:**
    * Ensure your user account has the necessary IAM roles to perform the setup, including:
        * **Kubernetes Engine Admin (`roles/container.admin`):** For creating and managing GKE clusters.
        * **TPU Admin (`roles/tpu.admin`):** For managing TPU resources.
        * **Service Account Admin (`roles/iam.serviceAccountAdmin`) and Project IAM Admin (`roles/resourcemanager.projectIamAdmin`) (or equivalent permissions):** To create service accounts and manage IAM policies for Workload Identity.
        * **Storage Admin (`roles/storage.admin`):** Required for creating buckets and for the Google Service Account (GSA) that will be used by workloads to access GCS.
    * Workload Identity is the recommended way for GKE pods to securely access Google Cloud services.

3.  **Tool Installation and Configuration:**
    * **Google Cloud CLI (`gcloud`):** Install and initialize the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install). Ensure it's updated:
        ```bash
        gcloud components update
        ```
    * **`kubectl`:** Install the Kubernetes command-line tool. `gcloud` can install it:
        ```bash
        gcloud components install kubectl
        ```
    * **Configure `gcloud`:** Set your default project ID and compute region.
        ```bash
        gcloud config set project YOUR_PROJECT_ID
        gcloud config set compute/region us-central1
        ```
        Replace `YOUR_PROJECT_ID` with your actual project ID. The region is set to `us-central1` as it generally offers good availability of various TPU resources. Always verify the [official documentation on TPU regions and zones](https://cloud.google.com/tpu/docs/regions-zones) for specific TPU types and the latest information.

4.  **Model Access (Gemma via Kaggle API):**
    * **Kaggle Account:** You need a Kaggle account.
    * **Accept Gemma License:** You must accept the Gemma model license terms and usage policy on Kaggle for the specific model version you intend to use.
    * **Kaggle API Credentials:**
        * You will need your Kaggle username and a Kaggle API key.
        * To get these, download your `kaggle.json` API token from your Kaggle account page (typically `https://www.kaggle.com/YOUR_USERNAME/account`, navigate to the "API" section, and click "Create New Token").
        * The downloaded `kaggle.json` file contains your username and key. You will use these individual values for Kubernetes secret literals.

5.  **Environment Variables (Recommended for your Local Shell):**
    * Set up local environment variables in your terminal:
        ```bash
        export PROJECT_ID="your-project-id" # Replace with your actual project ID
        export REGION="us-central1"
        export CLUSTER_NAME="jetstream-gemma-cluster" # Choose a name for your GKE cluster

        export KAGGLE_USERNAME="your_kaggle_username_from_kaggle_json" # IMPORTANT: Update this
        export KAGGLE_KEY="your_kaggle_key_from_kaggle_json"       # IMPORTANT: Update this

        export MODEL_NAME="gemma-2b-it" # Or another Gemma model variant like gemma-7b-it
        export MODEL_GCS_BUCKET_NAME="your-unique-bucket-name-${PROJECT_ID}" # Choose a unique GCS bucket name
        export MODEL_GCS_BUCKET="gs://${MODEL_GCS_BUCKET_NAME}"
        export CONVERTED_MODEL_GCS_PATH="${MODEL_GCS_BUCKET}/jetstream_checkpoints/${MODEL_NAME}"
        export TOKENIZER_GCS_PATH="${MODEL_GCS_BUCKET}/tokenizers/${MODEL_NAME}"

        # For Workload Identity
        export GSA_NAME="jetstream-gsa" # Google Service Account name
        export KSA_NAME="jetstream-ksa" # Kubernetes Service Account name
        export K8S_NAMESPACE="default" # Kubernetes namespace for KSA
        ```
        Ensure you replace placeholder values with your actual information. Create the GCS bucket: `gsutil mb -p $PROJECT_ID -l $REGION $MODEL_GCS_BUCKET` (You might need to enable "Uniform bucket-level access" during or after creation, or ensure ACLs are appropriate if not using uniform access).

6.  **TPU Quota:**
    * Verify that your project has sufficient quota for the TPU type you plan to use (e.g., TPU v5e, often requested as "TPU v5e Podslice" or similar for GKE Autopilot, which typically corresponds to `ct5lp-podslice` in quota terms). Check quotas in the Google Cloud Console under "IAM & Admin" > "Quotas" and request an increase if necessary.

