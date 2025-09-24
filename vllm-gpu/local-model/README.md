# Deploying a vLLM Server with a GCS Model and Persistent Volume

This document provides the steps to deploy a vLLM inference server on GKE, loading a model from a GCS bucket and using a Persistent Volume to cache the model data.

## Prerequisites

1.  A GKE cluster with a node pool that has GPUs and Workload Identity enabled.
2.  `kubectl` configured to communicate with your GKE cluster.
3.  A GCS bucket containing the model files.

## Deployment Steps

### Step 1: Configure Service Accounts and Workload Identity

These steps create a GCP service account, a Kubernetes service account, and binds them together to allow the pod to access GCS.

1.  **Set environment variables:**

    ```bash
    export GCP_PROJECT_ID=$(gcloud config get-value project)
    export K8S_NAMESPACE=default
    export K8S_SERVICE_ACCOUNT=vllm-sa
    export GCP_SERVICE_ACCOUNT=vllm-gcs-reader
    ```

2.  **Create the GCP Service Account:**

    ```bash
    gcloud iam service-accounts create ${GCP_SERVICE_ACCOUNT} \
      --display-name="vLLM GCS Reader"
    ```

3.  **Grant the GCP Service Account access to your GCS bucket:**
    Replace `gs://ai-llm-models` with the name of your bucket.

    ```bash
    gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
      --member="serviceAccount:${GCP_SERVICE_ACCOUNT}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
      --role="roles/storage.objectViewer"
    ```

4.  **Create the Kubernetes Service Account:**

    ```bash
    kubectl apply -f ./service-account.yaml
    ```

5.  **Bind the GCP and Kubernetes Service Accounts:**

    ```bash
    gcloud iam service-accounts add-iam-policy-binding \
      ${GCP_SERVICE_ACCOUNT}@${GCP_PROJECT_ID}.gserviceaccount.com \
      --role roles/iam.workloadIdentityUser \
      --member "serviceAccount:${GCP_PROJECT_ID}.svc.id.goog[${K8S_NAMESPACE}/${K8S_SERVICE_ACCOUNT}]"
    ```

6.  **Annotate the Kubernetes Service Account:**

    ```bash
    kubectl annotate serviceaccount ${K8S_SERVICE_ACCOUNT} \
      --namespace ${K8S_NAMESPACE} \
      iam.gke.io/gcp-service-account=${GCP_SERVICE_ACCOUNT}@${GCP_PROJECT_ID}.iam.gserviceaccount.com
    ```

### Step 2: Create the Persistent Volume Claim

This will create a persistent disk that will be used to cache the model, preventing re-downloads when pods restart.

```bash
kubectl apply -f ./persistent-volume-claim.yaml
```

### Step 3: Deploy the vLLM Server

Apply the deployment and service manifests to your cluster.

```bash
kubectl apply -f ./vllm-deployment.yaml
kubectl apply -f ./vllm-service.yaml
```

### Step 4: Verify the Deployment

Check the status of the deployment and pods. It may take several minutes for the pod to become ready as it needs to download the model files to the persistent volume for the first time.

```bash
kubectl get deployment vllm-gemma-1b
kubectl get pods -l app=vllm-gemma-1b
```

Once the pod is running, you can port-forward to the service to send inference requests:

```bash
kubectl port-forward service/vllm-gemma-1b-service 8000:80
```

---

## Troubleshooting Friction Log

This section documents the extensive troubleshooting process undertaken to debug issues with the GCS CSI driver and arrive at a stable solution using a persistent disk.

### Part 1: The GCS CSI Driver on GKE Autopilot

*   **Objective:** Deploy the vLLM server using the GCS CSI driver on an Autopilot cluster for a fully managed experience.
*   **Initial Problem:** The pod remained in a `Pending` state due to a lack of available `nvidia-l4` GPU nodes.
*   **New Issue:** Autopilot's attempt to provision a new GPU node failed with a `FailedScaleUp` event, indicating a temporary "out of resources" stockout for L4 GPUs in the `us-central1-b` zone.
*   **Persistent Problem:** After a node was eventually provisioned, the pod became stuck in `ContainerCreating`. The key event was `Warning FailedAttachVolume... timed out waiting for external-attacher`. This pointed to an issue with the CSI driver's control plane components.
*   **Root Cause on Autopilot:** Further investigation revealed that the vLLM pod was missing the `gcsfuse-proxy` sidecar container, which is essential for the volume mount. This was likely due to a conflict with the mandatory `warden-mutating` webhook on Autopilot, which could not be disabled.

### Part 2: Migrating to a GKE Standard Cluster

*   **Objective:** Move to a more flexible GKE Standard cluster to bypass the suspected webhook interference.
*   **Action:** A new GKE Standard cluster was created with a dedicated L4 GPU node pool.
*   **New Problem:** The `FailedAttachVolume` error returned, but with a more specific `PermissionDenied` message, indicating an IAM issue.
*   **Root Cause Analysis:** A diagnostic pod proved that Workload Identity was correctly configured, and the pod could get a valid token. The failure was definitively within the GCS CSI driver, which was not correctly using the pod's Workload Identity for the mount operation.

### Part 3: The Persistent Disk Caching Solution (SUCCESS)

*   **Objective:** Abandon the problematic GCS CSI driver and implement a more reliable model caching strategy.
*   **Action:** The configuration was reverted to use a standard `PersistentVolumeClaim` backed by a GCE persistent disk.
*   **Problem 1: `StorageClass not found`:** The initial deployment failed because the `standard-gce-pd` `StorageClass` does not exist by default.
    *   **Fix:** A manifest for the `standard-gce-pd` `StorageClass` was created and applied.
*   **Problem 2: `Failed to infer device type`:** The `vllm/vllm-openai:latest` container image failed to start, throwing a `RuntimeError`.
    *   **Fix:** Switched to a known-stable image tag, `vllm/vllm-openai:v0.4.0`.
*   **Problem 3: `gcloud` authentication:** The official Vertex AI container image failed to authenticate with GCS, as its internal scripts did not correctly use Workload Identity.
    *   **Fix:** An `initContainer` was added to the deployment. This container, using the `google/cloud-sdk:slim` image, correctly authenticates with Workload Identity and downloads the model to the persistent disk *before* the main vLLM container starts.
*   **Problem 4: vLLM Entrypoint:** The Vertex AI container's entrypoint script had issues with the provided arguments.
    *   **Fix:** The deployment was modified to explicitly call the vLLM python module, bypassing the problematic entrypoint script.
*   **Final Success:** After resolving these issues, the init container successfully downloaded the model, and the main vLLM container started correctly, loading the model from the persistent disk and serving inference requests.