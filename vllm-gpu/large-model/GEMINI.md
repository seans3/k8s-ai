# Project Overview

This directory contains Kubernetes manifests to deploy a VLLM (Very Large Language Model) inference server on a Google Kubernetes Engine (GKE) cluster.

The configuration is specifically designed to serve the `google/gemma-3-27b-it` model using the `vllm/vllm-openai:latest` container image. It is resource-intensive, requiring a node pool with at least 4 `nvidia-h100-80gb` GPUs.

The key components are:
*   `vllm-h100-deployment.yaml`: A Kubernetes Deployment that manages the VLLM server pods. It specifies the container image, resource limits (4 H100 GPUs), model to use, and other VLLM server arguments. It also requires a Kubernetes secret named `hf-secret` containing a Hugging Face API token.
*   `vllm-service.yaml`: A Kubernetes Service of type `ClusterIP` that exposes the VLLM deployment within the cluster on port 80, making the inference endpoint available to other applications in the same cluster.

# Building and Running

## Prerequisites

1.  A GKE cluster with a node pool that has `nvidia-h100-80gb` GPUs available.
2.  `kubectl` configured to communicate with your GKE cluster.
3.  A Hugging Face API token with access to the Gemma model.

## Useful commands

1. gcloud container clusters list
  * Shows a list of GKE clusters.
2. gcloud container node-pools
  * This command is the prefix for several commands to interact with GKE node pools.
3. gcloud container clusters get-credentials [CLUSTER_NAME] --region [REGION]
  * Gets kubectl credentials for a cluster and makes cluster the currently interacting cluster.
4. kubectl config current-context
  * Shows which Kubernetes cluster (by context) that I'm currently interacting with.
5. kubeclt config use-context <CONTEXT>
  * Changes cluster currently interacting with to the one identified by <CONTEXT>
6. kubectl apply -f <YAML>
  * Instantiates or updates a Kubernetes resource using its configuration YAML.


## Deployment Steps

1.  **Create the Hugging Face Secret:**
    Create a Kubernetes secret to securely store your Hugging Face API token.

    ```bash
    kubectl create secret generic hf-secret --from-literal=hf_api_token='YOUR_HUGGING_FACE_TOKEN'
    ```

2.  **Deploy the VLLM Server:**
    Apply the deployment and service manifests to your cluster.

    ```bash
    kubectl apply -f vllm-h100-deployment.yaml
    kubectl apply -f vllm-service.yaml
    ```

3.  **Verify the Deployment:**
    Check the status of the deployment and pods.

    ```bash
    kubectl get deployment vllm-gemma-3-27b
    kubectl get pods -l app=vllm-gemma-3-27b
    ```
    It may take several minutes for the pod to become ready as it needs to download the large model files.

# Development Conventions

*   **Kubernetes Best Practices:** The YAML manifests follow standard Kubernetes conventions for deployments and services.
*   **Labels for Observability:** The resources are labeled with `ai.gke.io/model` and `ai.gke.io/inference-server` to integrate with GKE's built-in observability features for AI/ML workloads.
*   **Resource Management:** The deployment explicitly requests `nvidia.com/gpu: 4` and sets a node selector for `nvidia-h100-80gb` to ensure the pods are scheduled on appropriate hardware.
