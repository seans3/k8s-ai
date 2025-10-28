# High-Performance VLLM Inference Server on GKE

This project provides Kubernetes manifests to deploy a [vLLM](https://github.com/vllm-project/vllm) inference server on a Google Kubernetes Engine (GKE) cluster. The configuration is optimized for serving very large language models (LLMs) like `google/gemma-3-27b-it` using multiple GPUs for high-throughput inference.

This guide focuses on the **validated configuration using NVIDIA A100 80GB GPUs** on a GKE Autopilot cluster.

## Overview

The primary goal of this project is to serve a multi-billion parameter model efficiently by leveraging tensor parallelism. This technique splits the model's weights across several GPUs, significantly accelerating inference speed and throughput.

### Key Concepts

*   **Tensor Parallelism:** The deployment is configured with `--tensor-parallel-size 4`. This means that instead of loading the entire model onto one GPU, VLLM shards the model across all four available GPUs. When a request arrives, all four GPUs work on their piece of the model simultaneously, drastically reducing latency.
*   **Single Node, Multiple GPUs:** GKE Autopilot provisions a single, powerful node (a virtual machine) that has four physical A100 GPUs attached to it. The VLLM pod runs on this single node and utilizes all four GPUs for its tensor parallel setup.

### VRAM Considerations: Why 80GB GPUs are Necessary

It is important to understand why GPUs with a large amount of VRAM (like the 80GB A100) are required, even when using tensor parallelism. The memory calculation is more complex than just the model's size.

The VRAM on each GPU in the tensor parallel group must be sufficient to hold its fraction of the model's weights **plus** the memory overhead for every request it is processing.

1.  **Model Weights:** The `gemma-3-27b-it` model has 27 billion parameters. When loaded in `bfloat16` precision (2 bytes per parameter), the model requires approximately **54 GB** of VRAM.
    *   With a tensor parallel size of 4, each GPU holds a shard of the weights: `54 GB / 4 = 13.5 GB`.

2.  **The KV Cache:** The most significant memory overhead comes from the Key-Value (KV) Cache. VLLM uses this cache to store the attention state of ongoing sequences, which dramatically speeds up token generation. The size of this cache depends on the number of concurrent requests and the context length (`--max-model-len`).
    *   For a large model with a long context length (like 16384 in our configuration), the KV cache can easily consume an additional **10-20 GB of VRAM per GPU** under load.

**Example Calculation for a single A100 80GB GPU:**
`13.5 GB (Model Shard) + ~15 GB (KV Cache) + ~2 GB (Framework Overhead) = ~30.5 GB`

This fits comfortably within the **80 GB** of VRAM on an A100. However, this calculation shows why a smaller GPU like an L4 (24 GB) would fail, as the required memory would exceed its capacity.

### Validated Configuration: NVIDIA A100

This is the configuration that has been successfully deployed and tested.

*   **Deployment:** `vllm-a100-deployment.yaml`
*   **Service:** `vllm-a100-service.yaml`
*   **GPU:** 4x `nvidia-a100-80gb`
*   **Container Image:** `vllm/vllm-openai:latest`

## Deployment Guide (A100 on GKE Autopilot)

Follow these steps to deploy and verify the VLLM server.

### 1. Prerequisites

*   **`gcloud` & `kubectl`**: Ensure both command-line tools are installed and configured to communicate with your Google Cloud project and GKE cluster.
*   **GKE Autopilot Cluster**: An existing GKE Autopilot cluster.
*   **GPU Quota**: Your project must have sufficient quota for `NVIDIA A100 80GB GPUs` in the region your cluster operates in.
*   **Hugging Face Token**: A Hugging Face API token. It is crucial to create a token with the **`read`** role. Fine-grained tokens may not have the necessary permissions to download gated models like Gemma.

### 2. Check for A100 GPU Availability

Before deploying, confirm which zones in your cluster's region have the required A100 GPUs.

```bash
# Replace us-central1 with your cluster's region
gcloud compute accelerator-types list \
  --filter="name='nvidia-a100-80gb' AND zone.region='us-central1'" \
  --format="table(name,zone)"
```

GKE Autopilot will automatically select one of the available zones from this list when provisioning the node.

### 3. Create the Hugging Face Secret

Create a Kubernetes secret to securely store your Hugging Face token.

```bash
kubectl create secret generic hf-secret --from-literal=hf_api_token='YOUR_HUGGING_FACE_TOKEN'
```

### 4. Deploy the VLLM Server

Apply the A100 deployment and service manifests to your cluster.

```bash
kubectl apply -f vllm-a100-deployment.yaml
kubectl apply -f vllm-a100-service.yaml
```

### 5. Monitor the Deployment

GKE Autopilot will now automatically provision a new node with four A100 GPUs. This process, along with the model download, can take **10-15 minutes**.

Monitor the pod's status until it shows `READY 1/1`.

```bash
# Check the pod status (it will be 'Pending' then 'ContainerCreating' then 'Running')
kubectl get pods -l app=vllm-gemma-3-27b-a100

# Once running, you can tail the logs to watch the model download
kubectl logs -f -l app=vllm-gemma-3-27b-a100
```

## Verification

Once the pod is ready, you can verify the inference server is working correctly.

### 1. Port-Forward to the Service

Open a **new terminal** and run the following command to forward a local port to the service running inside the cluster. Leave this terminal running.

```bash
kubectl port-forward service/vllm-gemma-3-27b-a100-service 8080:80
```

### 2. Send a Test Request

In your **original terminal**, use `curl` to send a prompt to the server via the local port-forward.

```bash
curl http://localhost:8080/v1/completions \
-H "Content-Type: application/json" \
-d 
'{
    "model": "gemma-3-27b-it",
    "prompt": "Why is the sky blue?",
    "max_tokens": 1000
}'
```

You should receive a JSON response containing a detailed explanation.

### 3. Clean Up

Stop the port-forwarding process by returning to its terminal and pressing `Ctrl+C`.

## Troubleshooting & Container Images

The choice of container image is critical for a successful deployment on GKE. It is recommended to use the `vllm/vllm-openai:latest` image and to set the `LD_LIBRARY_PATH` environment variable to `/usr/local/nvidia/lib64:/usr/local/cuda/lib64` to ensure compatibility with the GKE's managed NVIDIA drivers.

## Alternative Configuration (H100 - Untested)

This repository also contains a theoretical configuration for `nvidia-h100-80gb` GPUs in `vllm-h100-deployment.yaml`. This configuration has **not been validated** and would require:
1.  A GKE cluster with H100 GPU availability.
2.  Sufficient quota for H100 GPUs.
3.  A compatible container image that works with the GKE H100 driver environment.