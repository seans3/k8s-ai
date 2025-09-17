# VLLM AI Inference Server for Large Models

This project provides Kubernetes manifests to deploy a [vLLM](https://github.com/vllm-project/vllm) inference server on a Google Kubernetes Engine (GKE) cluster. The server is configured to serve large models like `google/gemma-3-27b-it`, which has over 27 billion parameters.

## Overview

The configuration is designed for high-performance inference, leveraging multiple GPUs for a single model. The key components are:

*   `vllm-h100-deployment.yaml`: A Kubernetes Deployment that manages the VLLM server pods.
*   `vllm-service.yaml`: A Kubernetes Service that exposes the VLLM server within the cluster.

This setup is resource-intensive and requires a GKE node pool with at least four `nvidia-h100-80gb` GPUs.

## Prerequisites

Before you begin, ensure you have the following:

1.  **GKE Cluster**: A GKE cluster with a node pool that has `nvidia-h100-80gb` GPUs available.
2.  **kubectl**: The `kubectl` command-line tool configured to communicate with your GKE cluster.
3.  **Hugging Face API Token**: A Hugging Face API token with access to the Gemma model. You can create a token in your Hugging Face account settings.

## Deployment

Follow these steps to deploy the vLLM inference server.

### 1. Create the Hugging Face Secret

Create a Kubernetes secret to securely store your Hugging Face API token. This allows the vLLM server to download the model from the Hugging Face Hub.

```bash
kubectl create secret generic hf-secret --from-literal=hf_api_token='YOUR_HUGGING_FACE_TOKEN'
```

### 2. Deploy the VLLM Server

Apply the deployment and service manifests to your cluster.

```bash
kubectl apply -f vllm-h100-deployment.yaml
kubectl apply -f vllm-service.yaml
```

### 3. Verify the Deployment

Check the status of the deployment to ensure the pod is running. It may take several minutes for the pod to become ready as it needs to download the large model files.

```bash
# Check the deployment status
kubectl get deployment vllm-gemma-3-27b

# Check the pod status
kubectl get pods -l app=vllm-gemma-3-27b

# View pod logs to monitor model download progress
kubectl logs -f -l app=vllm-gemma-3-27b
```

Once the pod is in the `Running` state, the vLLM server is ready to accept requests.

## Configuration

The `vllm-h100-deployment.yaml` file contains several configuration options that you can customize:

| Parameter | Description | Default Value |
|---|---|---|
| `replicas` | The number of vLLM server pods to run. | `1` |
| `cloud.google.com/gke-accelerator` | The type of GPU to use for the node selector. | `nvidia-h100-80gb` |
| `nvidia.com/gpu` | The number of GPUs to allocate to each pod. | `4` |
| `--model` | The name of the model to serve from the Hugging Face Hub. | `google/gemma-3-27b-it` |
| `--tensor-parallel-size` | The number of GPUs to use for tensor parallelism. This should match the number of GPUs allocated. | `4` |
| `--gpu-memory-utilization` | The percentage of GPU memory to use for the model. | `0.95` |
| `--max-model-len` | The maximum sequence length for the model. | `16384` |

To use a different model or adjust the resource allocation, modify these parameters in the `vllm-h100-deployment.yaml` file before applying the manifests.
