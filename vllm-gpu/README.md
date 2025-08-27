# AI Inference on GKE Autopilot with vLLM and Gemma

This guide provides a comprehensive walkthrough for deploying a vLLM-powered AI inference server for the Gemma model on Google Kubernetes Engine (GKE) Autopilot. By the end of this guide, you will have a scalable, GPU-accelerated endpoint for your AI model.

## 1. Deploy and Serve the Model

This section covers the core steps to get the vLLM server running and accessible.

### Step 1: Deploy the vLLM Server
Apply the deployment manifest to your GKE cluster. This will create a Kubernetes Deployment that manages the vLLM server pods.

```bash
kubectl apply -f vllm-deployment.yaml
```

### Step 2: Expose the Service
Apply the service manifest to expose the vLLM deployment within the cluster via a stable `ClusterIP`.

```bash
kubectl apply -f vllm-service.yaml
```

### Step 3: Monitor the Deployment
GKE Autopilot will automatically provision a GPU node for your workload, which may take several minutes. Monitor the pod status until it is `Running`.

```bash
# Watch the pods until they are in the "Running" state
kubectl get pods -l app=vllm-gemma-server -w

# (Optional) Wait for the deployment to be fully available (timeout of 15 minutes)
kubectl wait --for=condition=Available --timeout=900s deployment/vllm-gemma-deployment
```

### Step 4: Access and Test the Endpoint
Use `kubectl port-forward` to access the service from your local machine.

```bash
# In a new terminal, forward local port 8080 to the service's port 8081
kubectl port-forward service/vllm-service 8080:8081
```

With port forwarding active, send an inference request using `curl`:

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
-H "Content-Type: application/json" \
-d 
    "{
        \"model\": \"$MODEL_ID\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Explain Quantum Computing in simple terms.\"}]
    }"
```

---

## 2. Understanding the Configuration

The behavior of the inference server is defined in two key files:

- **`vllm-deployment.yaml`**: Defines the state of the vLLM server. Key fields include:
    - **`replicas`**: The number of vLLM instances.
    - **`image`**: The vLLM Docker image.
    - **`args`**: Command-line arguments for the vLLM server, including the model ID.
    - **`resources.limits`**: Specifies the required GPU resources (e.g., `nvidia.com/gpu: "1"`). **This is crucial for Autopilot to provision a GPU node.**
    - **`nodeSelector`**: Specifies the GPU type (e.g., `cloud.google.com/gke-accelerator: nvidia-l4`).

- **`vllm-service.yaml`**: Defines how to access the vLLM pods. It creates a stable internal IP address and DNS name for the service.

---

## 3. Advanced Topics

### Horizontal Pod Autoscaling (HPA)
For automatic scaling based on traffic, refer to the [Horizontal Pod Autoscaling guide](./hpa/README.md).

### Troubleshooting
- **View logs:** `kubectl logs -f -l app=vllm-gemma-server`
- **Describe pod:** `kubectl describe pod <pod-name>` to see events and configuration details.

---

## 4. Initial Setup (Prerequisites)

This is a one-time setup to prepare your environment.

### Step 1: Set Environment Variables
Set the following environment variables in your shell.

```bash
# Replace with your actual project ID
export PROJECT_ID="your-project-id"

# GKE cluster name
export CLUSTER_NAME="vllm-gemma-cluster"

# Google Cloud region
export REGION="us-central1"

# Hugging Face access token
export HF_TOKEN="your-hugging-face-token"

# The model to deploy
export MODEL_ID="google/gemma-2b-it"
```

### Step 2: Configure Google Cloud
- Select or create a [Google Cloud project](https://console.cloud.google.com/projectcreate).
- Ensure [billing is enabled](https://cloud.google.com/billing/docs/how-to/modify-project).
- Enable the **Kubernetes Engine API**:
  ```bash
  gcloud services enable container.googleapis.com
  ```
- Ensure you have `Kubernetes Engine Admin` IAM permissions.

### Step 3: Install Tools
- **Google Cloud CLI (`gcloud`):** Install the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install-sdk) and initialize it:
  ```bash
  gcloud init
  ```
- **`kubectl`:** Install via `gcloud`:
  ```bash
  gcloud components install kubectl
  ```

### Step 4: Get Hugging Face Token
- Create a [Hugging Face account](https://huggingface.co/join).
- Accept the license for your chosen model (e.g., [google/gemma-2b-it](https://huggingface.co/google/gemma-2b-it)).
- Generate an [access token](https://huggingface.co/docs/hub/en/security-tokens) with 'Read' permissions.

### Step 5: Create GKE Cluster and Kubernetes Secret
- Create the GKE Autopilot cluster:
  ```bash
  gcloud container clusters create-auto $CLUSTER_NAME \
      --project=$PROJECT_ID \
      --region=$REGION
  ```
- Connect `kubectl` to your new cluster:
  ```bash
  gcloud container clusters get-credentials $CLUSTER_NAME \
      --region=$REGION \
      --project $PROJECT_ID
  ```
- Create the Kubernetes secret for your Hugging Face token:
  ```bash
  kubectl create secret generic hf-secret \
      --from-literal=hf_token=$HF_TOKEN
  ```

---

## 5. Clean Up

To avoid ongoing charges, delete the resources you created.

```bash
# Delete Kubernetes resources
kubectl delete service vllm-service
kubectl delete deployment vllm-gemma-deployment
kubectl delete secret hf-secret

# Delete the GKE cluster
gcloud container clusters delete $CLUSTER_NAME \
    --region=$REGION \
    --project $PROJECT_ID
```