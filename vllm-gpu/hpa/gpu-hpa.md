# Autoscaling a vLLM Server with NVIDIA GPU Metrics

This guide provides a detailed walkthrough for configuring a Horizontal Pod Autoscaler (HPA) to scale a vLLM inference server based on NVIDIA GPU utilization. This approach uses the `dcgm_fi_dev_gpu_util` metric, which is a direct measure of how busy the GPU hardware is.

This method is ideal for GPU-bound workloads, as it ensures that the number of replicas scales up to meet high demand and, just as importantly, scales down when expensive GPU resources are underutilized.

**Prerequisites:**
*   A running GKE cluster (v1.27+) with GPU nodes and Managed Service for Prometheus enabled.
*   A deployed vLLM AI inference server as described in the [parent directory's README](../README.md).

---

## Step 1: Configure Prometheus Metric Collection for GPUs

GKE automatically deploys the NVIDIA Data Center GPU Manager (DCGM) exporter on nodes with GPUs. You need to configure Prometheus to scrape the metrics exposed by this exporter.

1.  **Verify the DCGM Exporter:**
    First, confirm that the `dcgm-exporter` pods are running in the `gke-managed-system` namespace.
    ```bash
    kubectl get pods -n gke-managed-system | grep dcgm-exporter
    ```

2.  **Apply the Monitoring Configuration:**
    Because the DCGM exporter resides in a managed, protected namespace, a standard `PodMonitoring` resource cannot be used. Instead, you must apply a `ClusterPodMonitoring` resource, which has the necessary permissions. The `gpu-rules.yaml` file is also applied to create a lowercase, HPA-compatible version of the GPU metric.
    ```bash
    kubectl apply -f ./gpu-pod-monitoring.yaml
    kubectl apply -f ./gpu-rules.yaml
    ```

3.  **Verify the Configuration:**
    Check that the metric `dcgm_fi_dev_gpu_util` is being collected by querying it in the **Metrics explorer** in the Google Cloud Console. This metric represents the percentage of time that the GPU's compute kernels were active and is the primary indicator of GPU load.

---

## Step 2: Deploy and Configure the Stackdriver Adapter

To allow the HPA to use the GPU metrics you've just collected, you must deploy the Custom Metrics Stackdriver Adapter.

Follow the detailed instructions in the appendix:
**[Appendix: Configuring the Stackdriver Adapter for HPA](./stackdriver-adapter-setup.md)**

---

## Step 3: Deploy the Horizontal Pod Autoscaler

Now you can deploy the HPA, which will monitor the `dcgm_fi_dev_gpu_util` metric and scale the `vllm-gemma-deployment` accordingly.

1.  **Apply the HPA Manifest:**
    The `gpu-horizontal-pod-autoscaler.yaml` manifest defines the scaling behavior. It targets an average GPU utilization of `20%`. If the average utilization across all pods exceeds this threshold, the HPA will add more replicas (up to a maximum of 5).
    ```bash
    kubectl apply -f ./gpu-horizontal-pod-autoscaler.yaml
    ```

2.  **Verify the HPA's Status:**
    Inspect the HPA to confirm it's active and has successfully read the metric.
    ```bash
    kubectl describe hpa/gemma-server-gpu-hpa
    ```
    Key things to check for:
    *   **Metrics:** The `Metrics` line should show the current GPU utilization against the target (e.g., `0 / 20`).
    *   **Conditions:** The `ScalingActive` condition should be `True` with the reason `ValidMetricFound`. This confirms the HPA can see and understand the metric from the Stackdriver Adapter.

---

## Step 4: Test the Autoscaling Functionality

Generate a sustained load on the inference server to increase GPU utilization and trigger an autoscaling event.

1.  **Expose the Service Locally:**
    ```bash
    kubectl port-forward service/llm-service 8081:8081
    ```

2.  **Start the Load Generator:**
    In a new terminal, run the provided `request-looper.sh` script to send a continuous stream of inference requests.
    ```bash
    ./request-looper.sh
    ```

3.  **Observe the Scaling Behavior:**
    As the script runs, the GPU utilization will increase. You can watch the HPA react to this change.
    ```bash
    # Watch the HPA's status and events in real-time
    kubectl describe hpa/gemma-server-gpu-hpa

    # In another terminal, watch the number of deployment replicas increase
    kubectl get deploy/vllm-gemma-deployment -w
    ```
    You will see a `SuccessfulRescale` event in the HPA's description, and the number of ready pods for the `vllm-gemma-deployment` will increase from 1 to the new target as utilization surpasses the 20% threshold.

---

## Step 5: Cleanup

To avoid ongoing charges, remember to delete the resources you've created.

*   **Option A: Delete HPA Resources Only:**
    ```bash
    kubectl delete hpa/gemma-server-gpu-hpa
    kubectl delete -f ./stack-driver-adapter.yaml
    kubectl delete namespace custom-metrics
    kubectl delete -f ./gpu-pod-monitoring.yaml
    kubectl delete -f ./gpu-rules.yaml
    ```

*   **Option B: Delete All Kubernetes Resources:**
    This removes the HPA components and the vLLM server itself.
    ```bash
    kubectl delete hpa/gemma-server-gpu-hpa
    kubectl delete -f ./stack-driver-adapter.yaml
    kubectl delete namespace custom-metrics
    kubectl delete -f ./gpu-pod-monitoring.yaml
    kubectl delete -f ./gpu-rules.yaml
    kubectl delete service llm-service
    kubectl delete deployment vllm-gemma-deployment
    kubectl delete secret hf-secret
    ```
