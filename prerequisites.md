# Prerequisites Guide for vLLM Inference Server on GKE Autopilot

1.  **Google Cloud Project Setup:**
    * Select or create a Google Cloud project.
    * Ensure billing is enabled for your project.
    * Enable the Kubernetes Engine API in your Google Cloud project.
2.  **IAM Permissions:**
    * Ensure your user account has the necessary IAM (Identity and Access Management) roles for creating and managing GKE clusters and related resources. This might include roles like "Kubernetes Engine Admin" and "Service Account User," or more granular permissions depending on your organization's policies.
3.  **Tool Installation & Configuration:**
    * **Google Cloud CLI (`gcloud`):** Install and initialize the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install).
    * **`kubectl`:** Install the Kubernetes command-line tool, `kubectl`. The `gcloud` CLI can often install this for you:
        ```bash
        gcloud components install kubectl
        ```
    * **Configure `gcloud`:** Set your default project ID and compute region.
        ```bash
        gcloud config set project YOUR_PROJECT_ID
        gcloud config set compute/region us-central1
        ```
        Replace `YOUR_PROJECT_ID` with your actual project ID. The region is set to `us-central1` as it generally offers good availability of various GPU and TPU resources. However, you should always verify the [Google Cloud documentation for regional availability](https://cloud.google.com/compute/docs/gpus/gpu-regions-zones) of specific accelerators if you have particular hardware needs or for the latest information.
4.  **Model Access (e.g., for Gemma from Hugging Face):**
    * **Sign License Agreement:** Many models, such as Gemma, require you to agree to their terms of use. For Gemma, this often involves signing a license consent agreement, for example, via Kaggle. Check the specific requirements for the model you intend to use.
    * **Hugging Face Access Token:** To download models from the Hugging Face Hub, you'll need an account and an access token.
        * Create a Hugging Face account if you don't have one.
        * Generate an access token with at least 'Read' permissions. You can find detailed instructions on how to create and manage your tokens on the [Hugging Face documentation](https://huggingface.co/docs/hub/en/security-tokens).
        * Keep this token secure; you will use it to create a Kubernetes secret.
5.  **Environment Variables (Recommended for your local shell):**
    * Set up local environment variables in your terminal session for convenience. This makes it easier to copy and paste commands without modification.
        ```bash
        export PROJECT_ID="your-project-id" # Replace with your actual project ID
        export REGION="us-central1" # Region is set to us-central1
        export CLUSTER_NAME="your-gke-cluster-name" # Choose a name for your cluster
        export HF_TOKEN="your-hugging-face-token" # Your actual Hugging Face token
        export MODEL_ID="google/gemma-1b-it" # 1 billion parameter (smallest) model
        ```
        Ensure you replace placeholder values like `your-project-id` with your actual information.
		
