# AI/ML Inference Recipes on Google Kubernetes Engine (GKE)

This repository is a collection of production-grade recipes and best practices for deploying and managing AI/ML inference workloads on Google Kubernetes Engine (GKE). It provides a series of well-documented, modular examples that cover a wide range of scenarios, from basic model serving to advanced, high-availability and cost-optimization patterns.

---

## Table of Contents

### Core Inference Serving Patterns

This section covers the foundational patterns for serving models on different types of hardware accelerators available in GKE.

-   **[Serving with vLLM on NVIDIA GPUs](./vllm-gpu/README.md)**
    This is the baseline recipe for deploying a high-performance vLLM inference server on a GKE Autopilot cluster. It demonstrates how to serve a Gemma model on a single NVIDIA L4 GPU, including the initial setup of the cluster and credentials.

-   **[Serving Large Models with Tensor Parallelism](./vllm-gpu/large-model/README.md)**
    This guide addresses the challenges of serving very large models (e.g., 27 billion parameters). It demonstrates how to use **tensor parallelism** to shard the model across multiple powerful GPUs (NVIDIA A100) on a single GKE node, significantly accelerating inference for demanding workloads.

-   **[Serving with JetStream on Cloud TPUs](./jetstream-tpu/README.md)**
    This recipe provides a complete walkthrough for serving LLMs on Google's custom AI accelerators. It covers the entire lifecycle, including converting the model to the JetStream-compatible format, configuring Workload Identity for secure GCS access, and deploying the server on a TPU-enabled GKE cluster.

### Production-Grade Patterns & Optimizations

This section provides advanced recipes for enhancing the reliability, efficiency, and scalability of your AI inference services.

-   **[Blue-Green Deployments for Zero-Downtime Updates](./blue-green/README.md)**
    This guide implements a high-availability **blue-green deployment strategy** using the GKE Gateway API. This pattern allows you to deploy a new version of a model to a "green" environment and atomically switch live traffic from the "blue" environment, enabling zero-downtime updates and providing an instantaneous rollback capability.

-   **[Efficient Multi-Model Serving with LoRA](./gateway/README.md)**
    This recipe demonstrates how to serve multiple, specialized models from a single GPU, drastically improving resource utilization. It uses the GKE Inference Gateway and **Low-Rank Adaptation (LoRA)** to apply lightweight, task-specific "adapters" to a single base model on the fly, reducing operational costs and complexity.

-   **[Automated Scaling with Horizontal Pod Autoscaler (HPA)](./vllm-gpu/hpa/README.md)**
    This guide provides two distinct strategies for automatically scaling your inference servers based on demand:
    1.  **vLLM Server Metrics:** Scales the deployment based on the number of concurrent requests being processed.
    2.  **NVIDIA GPU Metrics:** Scales based on raw GPU utilization, ensuring expensive hardware is never idle or oversubscribed.

-   **[Optimizing Startup with Persistent Volume Caching](./vllm-gpu/local-model/README.md)**
    This recipe solves the "cold start" problem of slow model downloads. It implements a robust caching strategy where an `initContainer` downloads the model from GCS to a **Persistent Volume** on the first startup. Subsequent pod restarts are nearly instantaneous, as the model is loaded directly from the local disk, dramatically improving scalability and recovery times.

### Simplified High-Level Abstractions



This section showcases how to simplify the deployment process by abstracting away the underlying complexity of Kubernetes and Google Cloud resources.



-   **[One-Step Deployments with KCC and KRO](./kcc-kro/README.md)**

    This guide uses a combination of **Kubernetes Config Connector (KCC)** and the **Kubernetes Resource Orchestrator (KRO)** to create high-level, custom resources like `GemmaOnNvidiaL4Server` and `GemmaOnTPUServer`. This allows you to deploy a complete, multi-component inference stack (including IAM, GCS, and Kubernetes resources) with a single, simple YAML file.



### Cluster Setup Tips



-   **[Tips and Tricks for GKE Cluster Setup](./tips-and-tricks.md)**

    This guide provides instructions on how to create cost-effective GPU node pools using Spot VMs, which is a great way to get access to high-demand GPUs for testing these recipes.
