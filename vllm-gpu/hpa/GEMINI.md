# Project Overview

This project provides the necessary Kubernetes resources and documentation to set up Horizontal Pod Autoscaling (HPA) for a vLLM AI inference server on Google Kubernetes Engine (GKE). The primary goal is to automatically scale the number of inference server pods based on demand, optimizing resource utilization and performance.

The project demonstrates two distinct autoscaling strategies:

1.  **vLLM Server Metrics:** Autoscaling based on the `vllm:num_requests_running` metric, which is exposed directly by the vLLM server. This approach scales the deployment based on the number of concurrent requests being processed.
2.  **NVIDIA GPU Metrics:** Autoscaling based on the `dcgm_fi_dev_gpu_util` metric, which represents the GPU utilization. This method, provided by the NVIDIA DCGM exporter, scales the deployment based on how busy the GPUs are.

The core technologies used in this project include:

*   **Kubernetes (GKE):** The container orchestration platform.
*   **Horizontal Pod Autoscaler (HPA):** The Kubernetes component responsible for autoscaling.
*   **Managed Prometheus on GKE:** The monitoring solution used to collect and store metrics.
*   **Stackdriver Custom Metrics Adapter:** A component that allows the HPA to consume custom metrics from Managed Prometheus.
*   **vLLM:** The AI inference server being scaled.
*   **NVIDIA DCGM:** The tool used for monitoring NVIDIA GPUs.

# Building and Running

This project does not have a traditional build process as it consists of Kubernetes manifests and documentation. The primary actions are applying these manifests to a GKE cluster.

## Key Commands

The following are the essential commands for deploying and managing the resources in this project. These commands are extracted from the markdown files (`vllm-hpa.md` and `gpu-hpa.md`).

### vLLM Metrics Based HPA

1.  **Apply PodMonitoring:**
    ```bash
    kubectl apply -f ./pod-monitoring.yaml
    ```
2.  **Deploy Stackdriver Adapter:**
    ```bash
    kubectl apply -f ./stack-driver-adapter.yaml
    ```
3.  **Deploy HPA:**
    ```bash
    kubectl apply -f ./horizontal-pod-autoscaler.yaml
    ```

### GPU Metrics Based HPA

1.  **Apply ClusterPodMonitoring and Rules:**
    ```bash
    kubectl apply -f ./gpu-pod-monitoring.yaml
    kubectl apply -f ./gpu-rules.yaml
    ```
2.  **Deploy Stackdriver Adapter:**
    ```bash
    kubectl apply -f ./stack-driver-adapter.yaml
    ```
3.  **Deploy HPA:**
    ```bash
    kubectl apply -f ./gpu-horizontal-pod-autoscaler.yaml
    ```

### Testing

To test the HPA, you can use the `request-looper.sh` script to generate load on the vLLM server.

1.  **Port-forward to the service:**
    ```bash
    kubectl port-forward service/llm-service 8081:8081
    ```
2.  **Run the load generation script:**
    ```bash
    ./request-looper.sh
    ```

# Development Conventions

The project follows standard Kubernetes conventions for writing YAML manifests. The documentation is well-structured and provides clear, step-by-step instructions for deploying and verifying the resources.

The use of separate markdown files for each HPA strategy (`vllm-hpa.md` and `gpu-hpa.md`) indicates a clear separation of concerns and makes the project easy to understand and follow.

The `request-looper.sh` script is a good example of a self-contained testing tool that can be used to validate the functionality of the HPA setup.
