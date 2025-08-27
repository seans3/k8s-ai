# Autoscaling a vLLM Server with Server Metrics

This guide provides a detailed walkthrough for configuring a Horizontal Pod Autoscaler (HPA) to scale a vLLM inference server based on its own custom metrics. Specifically, this approach uses the `vllm:num_requests_running` metric, which is a direct indicator of the server's current workload.

This method is ideal for scaling based on the actual number of concurrent requests being processed, ensuring that you have just the right number of pods to handle the load without wasting resources.

**Prerequisites:**
*   A running GKE cluster (v1.27+) with Managed Service for Prometheus enabled.
*   A deployed vLLM AI inference server as described in the [parent directory's README](../README.md).

---

## Step 1: Verify vLLM Server Metrics

First, ensure that your vLLM server is correctly exposing its metrics endpoint.

1.  **Expose the Service Locally:**
    Use `kubectl port-forward` to make the `llm-service` accessible from your local machine.
    ```bash
    kubectl port-forward service/llm-service 8081:8081
    ```

2.  **Query the Metrics Endpoint:**
    In a new terminal, use `curl` to access the `/metrics` endpoint and `grep` to confirm that the `num_requests_running` metric is present.
    ```bash
    curl -sS http://localhost:8081/metrics | grep num_requests_running
    ```
    The expected output should clearly show the metric:
    ```
    # HELP vllm:num_requests_running Number of requests currently running on GPU.
    # TYPE vllm:num_requests_running gauge
    vllm:num_requests_running{model_name="google/gemma-3-1b-it"} 0.0
    ```

3.  **Stop Port-Forwarding:**
    You can stop the `kubectl port-forward` command with `Ctrl+C`.

---

## Step 2: Configure Prometheus Metric Collection

With the metric endpoint verified, configure GKE's Managed Service for Prometheus to scrape these metrics.

1.  **Apply the `PodMonitoring` Manifest:**
    The `pod-monitoring.yaml` file contains a `PodMonitoring` custom resource. This resource instructs Prometheus to find pods with the label `app: gemma-server` and scrape metrics from port `8081` on the `/metrics` path every 15 seconds.
    ```bash
    kubectl apply -f ./pod-monitoring.yaml
    ```

2.  **Verify the Configuration:**
    Check the status of the `PodMonitoring` resource to ensure it was applied successfully.
    ```bash
    kubectl describe podmonitoring/gemma-pod-monitoring
    ```
    Look for a condition with `Type: ConfigurationCreateSuccess` and `Status: True`, which confirms that Prometheus has accepted the new scrape target. You can also verify that the metric appears in the Google Cloud Console's **Metrics explorer**.

---

## Step 3: Deploy and Configure the Stackdriver Adapter

To allow the HPA to use the metrics you've just collected, you must deploy the Custom Metrics Stackdriver Adapter.

Follow the detailed instructions in the appendix:
**[Appendix: Configuring the Stackdriver Adapter for HPA](./stackdriver-adapter-setup.md)**

---

## Step 4: Deploy the Horizontal Pod Autoscaler

Now you can deploy the HPA, which will monitor the `vllm:num_requests_running` metric and scale the `vllm-gemma-deployment` accordingly.

1.  **Apply the HPA Manifest:**
    The `horizontal-pod-autoscaler.yaml` manifest defines the scaling behavior. It targets an average value of `4` for the metric. If the average number of running requests per pod exceeds this threshold, the HPA will add more replicas (up to a maximum of 5).
    ```bash
    kubectl apply -f ./horizontal-pod-autoscaler.yaml
    ```

2.  **Verify the HPA's Status:**
    Inspect the HPA to confirm it's active and has successfully read the metric.
    ```bash
    kubectl describe hpa/gemma-server-hpa
    ```
    Key things to check for:
    *   **Metrics:** The `Metrics` line should show the current metric value against the target (e.g., `0 / 4`).
    *   **Conditions:** The `ScalingActive` condition should be `True` with the reason `ValidMetricFound`. This confirms the HPA can see and understand the metric from the Stackdriver Adapter.

---

## Step 5: Test the Autoscaling Functionality

Generate a sustained load on the inference server to trigger an autoscaling event.

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
    As the script runs, the average value of `vllm:num_requests_running` will increase. You can watch the HPA react to this change.
    ```bash
    # Watch the HPA's status and events in real-time
    kubectl describe hpa/gemma-server-hpa

    # In another terminal, watch the number of deployment replicas increase
    kubectl get deploy/vllm-gemma-deployment -w
    ```
    You will see a `SuccessfulRescale` event in the HPA's description, and the number of ready pods for the `vllm-gemma-deployment` will increase from 1 to the new target.

---

## Step 6: Cleanup

To avoid ongoing charges, remember to delete the resources you've created.

*   **Option A: Delete HPA Resources Only:**
    ```bash
    kubectl delete hpa/gemma-server-hpa
    kubectl delete -f ./stack-driver-adapter.yaml
    kubectl delete namespace custom-metrics
    kubectl delete podmonitoring/gemma-pod-monitoring
    ```

*   **Option B: Delete All Kubernetes Resources:**
    This removes the HPA components and the vLLM server itself.
    ```bash
    kubectl delete hpa/gemma-server-hpa
    kubectl delete -f ./stack-driver-adapter.yaml
    kubectl delete namespace custom-metrics
    kubectl delete podmonitoring/gemma-pod-monitoring
    kubectl delete service llm-service
    kubectl delete deployment vllm-gemma-deployment
    kubectl delete secret hf-secret
    ```
