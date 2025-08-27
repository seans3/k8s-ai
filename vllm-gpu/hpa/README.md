# Horizontal Pod Autoscaling for AI Inference Servers

This project demonstrates how to configure Horizontal Pod Autoscaling (HPA) for a vLLM-based AI inference server running on Google Kubernetes Engine (GKE). It provides the necessary Kubernetes manifests and instructions to automatically scale the number of inference server pods based on real-time demand, ensuring optimal resource utilization and performance.

Two distinct autoscaling strategies are presented:

1.  **Scaling based on vLLM Server Metrics:** This approach uses custom metrics directly from the vLLM server, specifically the number of running requests (`vllm:num_requests_running`), to make scaling decisions.
2.  **Scaling based on NVIDIA GPU Metrics:** This method leverages GPU utilization metrics (`dcgm_fi_dev_gpu_util`) provided by the NVIDIA Data Center GPU Manager (DCGM) to scale the deployment based on how busy the GPUs are.

## Prerequisites

*   A running GKE cluster (version 1.27 or later) with Managed Service for Prometheus enabled.
*   A deployed vLLM AI inference server, as described in the [parent directory's README](../README.md).
*   `kubectl` configured to communicate with your GKE cluster.
*   `gcloud` CLI installed and authenticated.

## Scaling Approaches

### 1. HPA using vLLM Server Metrics

This method scales the inference server based on the number of concurrent requests it is processing. It is a direct measure of the application's workload.

*   **Metric:** `vllm:num_requests_running`
*   **Description:** A gauge metric from the vLLM server indicating the number of requests currently running on the GPU.
*   **Configuration:** This setup involves a `PodMonitoring` resource to scrape the metrics and a `HorizontalPodAutoscaler` to act on them.

For detailed instructions, see: **[vLLM AI Inference Server HPA Guide](./vllm-hpa.md)**

### 2. HPA using NVIDIA GPU Metrics

This method scales the server based on the actual utilization of the underlying GPU hardware. This is useful for identifying if the workload is GPU-bound and for preventing underutilization of expensive GPU resources.

*   **Metric:** `dcgm_fi_dev_gpu_util`
*   **Description:** A gauge metric from the NVIDIA DCGM exporter representing the percentage of time one or more compute kernels were executing on the GPU.
*   **Configuration:** This setup requires a `ClusterPodMonitoring` resource to collect GPU metrics from the `gke-managed-system` namespace and a `HorizontalPodAutoscaler`.

For detailed instructions, see: **[vLLM AI Inference Server HPA with GPU Metrics Guide](./gpu-hpa.md)**

## Key Components

*   **HorizontalPodAutoscaler (HPA):** The core Kubernetes resource that automatically scales the number of pods in a deployment.
*   **PodMonitoring/ClusterPodMonitoring:** Custom resources provided by GKE's Managed Service for Prometheus to configure metrics scraping from pods.
*   **Stackdriver Adapter:** A component that exposes metrics from Managed Prometheus to the HPA controller.
*   **`request-looper.sh`:** A simple shell script to generate load for testing the autoscaling functionality.
