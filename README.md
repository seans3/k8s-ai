# Summary: AI Inference (GKE/GPU/vLLM/gemma)

Before you begin, ensure you have completed all necessary setup steps.
Please see the [Prerequisites Guide](./prerequisites.md) for detailed instructions.

## I. Create and Configure Google Cloud Resources

1.  **Create a GKE Autopilot Cluster:**
    * GKE Autopilot manages your cluster's nodes, automatically provisioning resources like GPUs when your workloads request them. You do not need to manually create and configure GPU node pools. The `$REGION` variable (set to `us-central1` in prerequisites) will be used here.
    * Create a GKE Autopilot cluster:
        ```bash
        gcloud container clusters create-auto $CLUSTER_NAME \
            --project=$PROJECT_ID \
            --region=$REGION
        ```
        *(Note: Autopilot cluster creation might take a few minutes. You can add `--release-channel=rapid` or other configurations if needed, similar to Standard clusters.)*
    * Connect `kubectl` to your GKE Autopilot cluster:
        ```bash
        gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION --project $PROJECT_ID
        ```
2.  **Create Kubernetes Secret for Hugging Face Token:**
    * Store your Hugging Face token as a Kubernetes secret. This allows pods in your GKE cluster to securely authenticate with Hugging Face to download model files.
        ```bash
        kubectl create secret generic hf-secret \
            --from-literal=hf_token=$HF_TOKEN
        ```

## II. Deploy vLLM

1.  **Define Kubernetes Deployment YAML:**
    * Create a `vllm-deployment.yaml` file using the raw YAML content provided separately. This file defines a Kubernetes Deployment resource that manages your vLLM pods.
    * Refer to the [vllm-deployment.yaml](./vllm-deployment.yaml) file (which you will create with the provided YAML content).
    * **Key configurations in this file include:**
        * `spec.replicas`: Number of vLLM instances.
        * `spec.template.spec.containers`:
            * `image`: The vLLM Docker image (eg. pytorch-vllm-serve)
            * `env`: Environment variables, including `HF_TOKEN` (mounted from the secret).
            * `args`: Command-line arguments for the vLLM server, such as `--model`, model name, `--port 8000`, and potentially `--tensor-parallel-size`.
            * `resources.limits`: **Crucially, specify the GPU resources required (e.g., `nvidia.com/gpu: "1"`)**. This tells Autopilot to provision a node with the requested GPU type for this pod. You might also need to add a `nodeSelector` for the specific GPU type if not using default Autopilot GPU classes (e.g., `cloud.google.com/gke-accelerator: nvidia-l4`).
            * `ports.containerPort`: The port vLLM listens on (typically 8000).
            * Readiness and Liveness probes to ensure pod health.
2.  **Apply the Deployment Manifest:**
    * Deploy vLLM to your GKE cluster using `kubectl`:
        ```bash
        kubectl apply -f vllm-deployment.yaml
        ```
3.  **Monitor Deployment Status:**
    * Check the status of your pods. Autopilot will take some time to provision a GPU node if one isn't already available that meets the workload's requirements.
        ```bash
        kubectl get pods -l app=gemma-server -w # Assuming your deployment has label app=gemma-server
        kubectl wait --for=condition=Available --timeout=900s deployment/vllm-gemma-deployment # Adjust name, timeout might need to be longer for initial GPU node provisioning
        ```
4.  **View Logs (Recommended):**
    * Check the logs from the vLLM pods to ensure the model is downloading and the server starts correctly:
        ```bash
        kubectl logs -f -l app=gemma-server # Adjust label selector
        ```
    * The logs will look something like
	    ```bash
        INFO:     Automatically detected platform cuda.
        ...
        INFO      [launcher.py:34] Route: /v1/chat/completions, Methods: POST
        ...
        INFO:     Started server process [13]
        INFO:     Waiting for application startup.
        INFO:     Application startup complete.
        Default STARTUP TCP probe succeeded after 1 attempt for container "vllm--google--gemma-3-1b-it-1" on port 8000.
        ```

## III. Serve the Model (Expose and Interact)

1.  **Define Kubernetes Service YAML (as ClusterIP):**
    * Create a `vllm-service.yaml` file using the raw YAML content provided separately. This defines a Kubernetes Service to expose your vLLM deployment internally within the cluster.
    * Refer to the [vllm-service.yaml](./vllm-service.yaml) file (which you will create with the provided YAML content).
    * **Key configurations in this file include:**
        * `type: ClusterIP`: This makes the service reachable only from within the GKE cluster. For local testing/development, you will typically use `kubectl port-forward`.
        * `spec.selector`: Must match the labels of your vLLM deployment's pods.
        * `spec.ports`: Define the port the service listens on (e.g., `port: 8000`) and the `targetPort` (the container port of vLLM, usually 8000, or its named port).
2.  **Apply the Service Manifest:**
    ```bash
    kubectl apply -f vllm-service.yaml
    ```
3.  **Accessing the Service (via Port Forwarding for Local Testing):**
    * Since `ClusterIP` services are not directly accessible externally, use `kubectl port-forward` to forward traffic from your local machine to the service within the cluster.
        ```bash
        # Forward a local port (e.g., 8080) to the service port (e.g., 8000)
        kubectl port-forward service/vllm-gemma-service 8080:8000 # Adjust service name, local port, and service port as needed
        ```
        Now, requests to `localhost:8080` on your machine will be forwarded to port `8000` on the `vllm-gemma-service` inside GKE.
4.  **Interact with the Model:**
    * **Using `curl` (via port-forward):** Send HTTP POST requests to `localhost` on the port you forwarded.
        ```bash
        curl -X POST http://localhost:8080/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "google/gemma-3-1b-it",
            "messages": [{"role": "user", "content": "Explain Quantum Computing in simple terms."}]
        }'
        ```
    * **(Optional) Gradio Interface:** If the tutorial includes a Gradio UI, it would typically be deployed as another service within the cluster that communicates with the `vllm-gemma-service` (ClusterIP). You would then port-forward to the Gradio service to access its UI.

## IV. Observe and Troubleshoot

* Use `kubectl logs deployment/<deployment-name>` to view logs.
* Use `kubectl describe pod <pod-name>` to get detailed information about a specific pod, including events. Note that with Autopilot, node-level details are abstracted.
* Monitor GPU utilization and performance using Cloud Monitoring.

## V. Clean Up

* Delete the Kubernetes resources:
    ```bash
    kubectl delete service vllm-gemma-service # Adjust name
    kubectl delete deployment vllm-gemma-deployment # Adjust name
    kubectl delete secret hf-secret
    ```
* Delete the GKE Autopilot cluster to avoid ongoing charges (uses $REGION which is set to `us-central1`):
    ```bash
    gcloud container clusters delete $CLUSTER_NAME --region=$REGION --project $PROJECT_ID
    ```
* Remove any other Google Cloud resources created.

**Note:** Always refer to the specific YAML files and detailed commands in the official Google Cloud documentation. For GKE Autopilot, pay close attention to how GPU types are requested in your workload manifest (e.g., using `resources.limits` and potentially `nodeSelector` for specific accelerator types available in Autopilot like `cloud.google.com/gke-accelerator: nvidia-tesla-t4` or `cloud.google.com/gke-accelerator: nvidia-l4`).
