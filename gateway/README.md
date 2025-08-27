# GKE Inference Gateway for Multi-Model Serving

This guide provides instructions for deploying a GKE Inference Gateway to serve multiple AI models using the VLLM inference server.

## Overview & Architecture

The **GKE Inference Gateway** is a managed, high-performance solution for deploying and managing AI/ML inference workloads on GKE. It provides a single, stable entry point (an Internal Load Balancer) to route requests to multiple, independently deployed models. This architecture is ideal for production environments as it simplifies client configuration, centralizes access control, and leverages GKE's native capabilities for autoscaling and GPU management.

The implementation follows a clear, three-tiered architecture:

1.  **GPU Node Pool (`inference-pool.yaml`)**: A dedicated GKE `NodePool` is provisioned with NVIDIA L4 GPUs. It is configured to autoscale and can scale down to zero nodes when not in use, providing significant cost savings. All model inference pods are scheduled exclusively on this pool.

2.  **Model Deployments & Services (`vllm-deployment.yaml`, `vllm-service.yaml`)**: The VLLM inference server is deployed as a separate Kubernetes `Deployment`. This isolates the workload, allowing it to be scaled and updated independently. The `Deployment` is exposed internally by a `ClusterIP` `Service`, which provides a stable network endpoint for the gateway to target.

3.  **Inference Gateway (`gateway.yaml`, `httproute.yaml`)**: The `InferenceGateway` custom resource is the core of this architecture. It automatically provisions a Google Cloud Internal Load Balancer and is configured with routing rules defined in the `HTTPRoute` resource. It inspects the request path and forwards traffic to the appropriate backend `Service`.

4. **Inference Models (`inference-model.yaml`)**: The `InferenceModel` custom resources define the models that will be served by the inference server. This allows for dynamic model management and versioning.

---
## LoRA and Efficient Multi-Model Serving

A key feature of this setup is the use of **Low-Rank Adaptation (LoRA)** to serve multiple specialized models efficiently. Instead of deploying a full, separate large language model for each task, we load a single base model into GPU memory and then apply lightweight "adapters" for each specific use case.

### What is LoRA?

LoRA (Low-Rank Adaptation) is a parameter-efficient fine-tuning (PEFT) technique that significantly reduces the cost and complexity of adapting large language models to new tasks. Instead of retraining all of a model's billions of parameters, LoRA freezes the original weights and injects small, trainable matrices into the model's architecture. These matrices, or "adapters," are the only components that are updated during fine-tuning.

The key benefits of this approach are:

*   **Reduced Computational Cost**: Training only the small adapter matrices is significantly faster and requires less GPU memory than full model fine-tuning.
*   **Smaller Model Artifacts**: LoRA adapters are typically only a few megabytes in size, compared to the gigabytes required for a full model. This makes them easier to store, manage, and distribute.
*   **Efficient Task Switching**: Since the base model remains in memory, you can switch between different tasks by simply swapping out the lightweight LoRA adapters, which is much faster than loading a new large model.

### LoRA in This Project

This project demonstrates the power of LoRA for multi-model serving. Here’s how it works:

1.  **Base Model**: The `vllm-deployment.yaml` specifies a base model (`google/gemma-3-1b-it`) that is loaded into the VLLM inference server. This is the large, general-purpose model that resides in GPU memory.
2.  **LoRA Adapters**: The `ConfigMap` named `vllm-gemma3-1b-adapters` defines the LoRA adapters that will be applied to the base model. In this case, it defines the `food-review` model, which is a fine-tuned adapter for a specific task.
3.  **Dynamic Loading**: The `lora-adapter-syncer` init container reads this `ConfigMap` and ensures that the specified LoRA adapters are downloaded and made available to the VLLM server.
4.  **Inference Requests**: When you make a request to the gateway and specify the `food-review` model, the VLLM server applies the corresponding LoRA adapter to the base Gemma model on the fly to generate the response. A request for the base model (`meta-llama/Llama-3.1-8B-Instruct`) will use the unmodified base model.

This architecture allows you to serve a base model and numerous specialized, fine-tuned models from a single GPU, dramatically improving resource utilization and reducing operational costs.

---

## Deployment Instructions

### Prerequisites

1.  A configured Google Cloud project and authenticated `gcloud`/`kubectl` CLI. For a detailed guide on setting up your environment from scratch, see [SETUP.md](SETUP.md).
2.  A GKE cluster with the Inference Gateway feature enabled. The instructions below use a GKE Standard cluster, but GKE Autopilot is also supported with configuration adjustments.
3.  A Kubernetes secret named `hf-secret` in the `default` namespace containing your Hugging Face token with at least 'Read' permissions. See [SETUP.md](SETUP.md) for instructions.
4.  Sufficient NVIDIA L4 GPU quota in your GCP project for the selected region.


### Step 1: Create the GPU Node Pool

This manifest provisions the necessary GPU hardware for the inference workloads.

```bash
kubectl apply -f inference-pool.yaml
```

### Step 2: Deploy the VLLM Inference Server

Deploy the VLLM inference server, which includes the Deployment and Service.

```bash
kubectl apply -f vllm-deployment.yaml
kubectl apply -f vllm-service.yaml
```

### Step 3: Deploy the Inference Gateway and Routing

This manifest creates the InferenceGateway, the associated HTTPRoute for routing, and the inference models.

```bash
kubectl apply -f gateway.yaml
kubectl apply -f httproute.yaml
kubectl apply -f inference-model.yaml
```

### Step 4: Verify and Test

Before sending test requests, it's important to verify that all the components of the inference gateway have been deployed and initialized successfully.

**1. Check the VLLM Pod Status**

First, check the status of the VLLM deployment to ensure the pods are running and have successfully downloaded the models.

```bash
kubectl get pods -l app=gemma-server
```

Wait until the pod status is `Running`. If the status is `ImagePullBackOff` or `ErrImagePull`, there may be an issue with the image registry or node networking. If the pod is `CrashLoopBackOff`, use `kubectl logs <pod-name>` to inspect the logs for errors.

**2. Verify the Service is Active**

Next, confirm that the `llm-service` is active and has been assigned a `CLUSTER-IP`.

```bash
kubectl get service llm-service
```

You should see an output with a valid IP address listed under the `CLUSTER-IP` column.

**3. Get the Gateway IP Address**

It may take a few minutes for the load balancer to be provisioned. Check the status and get the IP address with the following command:

```bash
GATEWAY_IP=$(kubectl get gateway ai-inf-gateway -o jsonpath='{.status.addresses[0].value}')
echo "Gateway IP: $GATEWAY_IP"
```

If the command returns an empty string, wait a few minutes and try again. The IP address is assigned by the Google Cloud Load Balancer, and provisioning can sometimes take time.

**4. Test the Endpoints**

Once you have confirmed that the pods are running, the service is active, and the gateway has an IP address, you can send inference requests to each model through the gateway from a VM or pod within the same VPC network.

Test the Gemma model:

```bash
curl http://${GATEWAY_IP}/v1/chat/completions \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-3-1-it",
    "messages": [
      {
        "role": "user",
        "content": "What is the meaning of life?"
      }
    ]
  }'
```


Test the Food Review model:

```bash
curl http://${GATEWAY_IP}/v1/chat/completions \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{ "model": "food-review", "messages": [ { "role": "user", "content": "What is the meaning of life?" } ] }'
```


A successful response will be a JSON object containing the model's output. If the request times out or returns an error, double-check the pod logs and ensure that the gateway IP is correct.


### Cleanup

To remove all the resources created in this guide, delete the Kubernetes objects and the GKE node pool.

#### Delete the Kubernetes Resources:

```bash
kubectl delete -f gateway.yaml,httproute.yaml,inference-model.yaml,vllm-service.yaml,vllm-deployment.yaml
```

#### Delete the GPU Node Pool:

```bash
gcloud container node-pools delete inference-pool \
  --cluster YOUR_CLUSTER_NAME \
  --region=YOUR_COMPUTE_REGION
```