# AI Inference on GKE using KCC and KRO

This project provides a streamlined way to deploy and serve AI models on Google Kubernetes Engine (GKE) using a combination of [Kubernetes Config Connector (KCC)](https://cloud.google.com/config-connector/docs/overview) and the [Kubernetes Resource Orchestrator (KRO)](https://kro.run/).

- **Config Connector (KCC):** Allows you to manage Google Cloud resources using Kubernetes-native syntax.
- **Kubernetes Resource Orchestrator (KRO):** Enables the creation of custom, high-level abstractions (like a complete inference server) from multiple underlying Kubernetes and cloud resources.

This guide demonstrates how to serve Gemma models on two different hardware configurations:
1.  **NVIDIA L4 GPUs** with [vLLM](https://docs.vllm.ai/en/latest/) for high-throughput serving.
2.  **Google Cloud TPUs** with [JetStream](https://github.com/google/jetstream-pytorch) for large-scale, low-latency inference.

## Prerequisites

Before you begin, you need the following tools and a configured Google Cloud project:
- `gcloud` CLI
- `kubectl`
- `helm`
- A Google Cloud project with billing enabled.
- A GKE Autopilot cluster.

For detailed, step-by-step instructions on how to set up your entire environment from scratch, please follow the **[Setup Guide](SETUP.md)**.

## Deploying AI Inference Services

Once you have completed the setup guide, you can deploy the inference services.

### 1. Gemma on NVIDIA L4 GPU with vLLM

This setup serves the [google/gemma-3-1b-it](https://huggingface.co/google/gemma-3-1b-it) model on an NVIDIA L4 GPU using the vLLM inference server.

**To deploy the server, apply the following Kubernetes resource:**

```bash
# Ensure the NAMESPACE environment variable is set to the one you created during setup.
# For example: export NAMESPACE=config-connector
kubectl apply -f - <<EOF
apiVersion: kro.run/v1alpha1
kind: GemmaOnNvidiaL4Server
metadata:
  name: gemma-l4
  namespace: ${NAMESPACE}
spec:
  replicas: 1
EOF
```
> **Note:** The `.spec.replicas` field is currently required.

**Verify the resources are created:**
```bash
# Check for the Deployment and Service
kubectl get deployment -n ${NAMESPACE}
kubectl get service -n ${NAMESPACE}
```

#### Querying the GPU Inference Server

1.  **Forward a local port to the service:**
    The service `gemma-l4` exposes the inference endpoint on port `8081`.

    ```bash
    kubectl port-forward svc/gemma-l4 -n ${NAMESPACE} 8081:8081
    ```

2.  **Send a request using `curl`:**
    In a new terminal, query the model through the local port.

    ```bash
    curl http://127.0.0.1:8081/v1/chat/completions \
    -X POST \
    -H "Content-Type: application/json" \
    -d 
    {
        "model": "google/gemma-3-1b-it",
        "messages": [
            {
              "role": "user",
              "content": "Why is the sky blue?"
            }
        ]
    }
    ```

### 2. Gemma on Cloud TPU with JetStream

This setup serves the [Gemma 7B model](https://www.kaggle.com/models/google/gemma) on Cloud TPUs using the JetStream inference server.

When you apply the custom resource, it automates the following steps:
1.  Creates necessary IAM service accounts and permissions.
2.  Creates a Google Cloud Storage bucket for model assets.
3.  Runs a Kubernetes Job to convert the Kaggle model into the JetStream format.
4.  Deploys the JetStream inference server.
5.  Exposes the server with a Kubernetes Service.

**To deploy the server, apply the following Kubernetes resource:**

```bash
# Ensure PROJECT_ID and NAMESPACE are set.
# For example: export PROJECT_ID=k8sai-myuser
#              export NAMESPACE=config-connector
kubectl apply -f - <<EOF
apiVersion: kro.run/v1alpha1
kind: GemmaOnTPUServer
metadata:
  name: gemma-tpu
  namespace: ${NAMESPACE}
spec:
  project: ${PROJECT_ID}
EOF
```

**Verify the resources are created:**
You can watch the progress as KCC and KRO create the necessary resources.
```bash
# Check IAM, Storage, and Kubernetes resources
kubectl get iamserviceaccount,iampolicymember,iampartialpolicy -n ${NAMESPACE}
kubectl get storagebucket -n ${NAMESPACE}
kubectl get job,deployment,service -n ${NAMESPACE}
```

#### Querying the TPU Inference Server

1.  **Forward a local port to the service:**
    The service `gemma-tpu` exposes the inference endpoint on port `8000`.

    ```bash
    kubectl port-forward svc/gemma-tpu -n ${NAMESPACE} 8000:8000
    ```

2.  **Send a request using `curl`:**
    In a new terminal, query the model.

    ```bash
    curl --request POST \
    --header "Content-type: application/json" \
    -s \
    localhost:8000/generate \
    --data 
    {
        "prompt": "What are the top 5 programming languages",
        "max_tokens": 200
    }
    ```

    You should see a JSON response with the model's output.

## Cleanup

To remove all the deployed resources and clean up your project, follow the **[Cleanup Guide](SETUP.md#7-cleanup)**.