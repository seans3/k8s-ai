# Deploying vLLM with Local Models on GKE

This document provides the steps to deploy a vLLM inference server on GKE, loading various open-source models from a GCS bucket and using a Persistent Volume to cache the model data.

This document provides the steps to deploy a vLLM inference server on GKE, loading various open-source models from a GCS bucket and using a Persistent Volume to cache the model data.

## Available Models

This directory contains the configurations to deploy several popular open-source models. The table below outlines the specific YAML files and hardware requirements for each model.

| Model Name | Deployment File | Service File | PVC File | GPU Type | GPU # | PVC Size |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `gemma-1b` | `vllm-deployment.yaml` | `vllm-service.yaml` | `persistent-volume-claim.yaml` | `nvidia-l4` | 1 | `50Gi` |
| `gemma-27b` | `vllm-deployment-gemma-27b.yaml` | `vllm-service-gemma-27b.yaml` | `persistent-volume-claim-gemma-27b.yaml` | `nvidia-tesla-a100` | 4 | `150Gi` |
| `gpt-oss-20b` | `vllm-deployment-gpt-oss-20b.yaml` | `vllm-service-gpt-oss-20b.yaml` | `persistent-volume-claim-gpt-oss-20b.yaml` | `nvidia-tesla-a100` | 4 | `200Gi` |
| `gpt-oss-120b` | `vllm-deployment-gpt-oss-120b.yaml` | `vllm-service-gpt-oss-120b.yaml` | `persistent-volume-claim-gpt-oss-120b.yaml` | `nvidia-a100-80gb` | 8 | `250Gi` |

## Prerequisites

1.  A GKE cluster with a node pool that has GPUs and Workload Identity enabled.
2.  `kubectl` configured to communicate with your GKE cluster.
3.  A GCS bucket containing the model files.

## Deployment Steps

### Step 1: Configure Service Accounts and Workload Identity

TODO: Update these steps to use [GKE Federation Identity](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)

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
      ${GCP_SERVICE_ACCOUNT}@${GCP_PROJECT_ID}.iam.gserviceaccount.com \
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

This will create a persistent disk that will be used to cache the model, preventing re-downloads when pods restart. Choose the appropriate `persistent-volume-claim-*.yaml` file from the table above for the model you want to deploy.

```bash
# Replace <model-pvc-file> with the correct yaml file (e.g., persistent-volume-claim-gemma-27b.yaml)
kubectl apply -f ./<model-pvc-file>
```

### Step 3: Deploy the vLLM Server

Apply the deployment and service manifests to your cluster. Choose the appropriate `vllm-deployment-*.yaml` and `vllm-service-*.yaml` files from the table above for the model you want to deploy.

```bash
# Replace <model-deployment-file> and <model-service-file> with the correct yaml files
kubectl apply -f ./<model-deployment-file>
kubectl apply -f ./<model-service-file>
```

### Step 4: Verify the Deployment

Check the status of the deployment and pods. It may take several minutes for the pod to become ready as it needs to download the model files to the persistent volume for the first time. Replace `<model-deployment-name>` and `<model-app-label>` with the correct names for the model you deployed.

```bash
kubectl get deployment <model-deployment-name>
kubectl get pods -l app=<model-app-label>
```

Once the pod is running, you can port-forward to the service to send inference requests. Replace `<model-service-name>` with the correct name for the model you deployed.

```bash
kubectl port-forward service/<model-service-name> 8000:80
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
*   **Problem 2: Container Image and Driver Incompatibility:** The `vllm/vllm-openai:latest` container image can sometimes have incompatibilities with the NVIDIA drivers on the GKE nodes, leading to CUDA errors.
    *   **Fix:** Ensure that the `LD_LIBRARY_PATH` environment variable is set in your deployment YAML to point to the correct NVIDIA and CUDA library paths. This helps the vLLM container find the correct drivers on the node.

      ```yaml
      env:
      - name: LD_LIBRARY_PATH
        value: "/usr/local/nvidia/lib64:/usr/local/cuda/lib64"
      ```
*   **Problem 3: vLLM Entrypoint:** The Vertex AI container's entrypoint script had issues with the provided arguments.
    *   **Fix:** The deployment was modified to explicitly call the vLLM python module, bypassing the problematic entrypoint script.
*   **Final Success:** After resolving these issues, the init container successfully downloaded the model, and the main vLLM container started correctly, loading the model from the persistent disk and serving inference requests.

---

## Architecture and Performance Benefits

The architecture of using an `initContainer` to download a model from GCS to a Persistent Disk was chosen for significant performance and reliability gains over other common methods, such as downloading a model directly from Hugging Face on container startup.

### Initial Startup Speed

For the very first time a pod starts, the model must be downloaded. This architecture provides a speed advantage by leveraging the high-bandwidth network between Google Cloud Storage and GKE.

*   **This Project (GCS -> Persistent Disk):** The model is transferred within Google Cloud's network, which is significantly faster and more reliable than downloading over the public internet.
*   **Direct Hugging Face Download:** The model is pulled from Hugging Face's servers over the public internet, which is subject to network congestion and will generally be slower.

### Subsequent Startup Speed (The Key Advantage)

The most critical performance benefit comes from caching the model on a persistent disk. When a pod needs to restart (due to scaling, node upgrades, or crashes), the download step is completely skipped.

*   **This Project (GCS -> Persistent Disk):** On restart, Kubernetes re-attaches the existing persistent disk. The vLLM server finds the model files already present and loads them directly from local disk, resulting in an extremely fast startup time.
*   **Direct Hugging Face Download:** On every restart, the pod's ephemeral storage is empty. The server must download the entire multi-gigabyte model from Hugging Face all over again, making every startup slow and dependent on external network conditions.

### Summary

| Startup Type | This Project (GCS + PD Cache) | Direct Hugging Face Download | Winner |
| :--- | :--- | :--- | :--- |
| **Initial Startup** | Very fast download from GCS. | Slower download from public internet. | **This Project** |
| **Subsequent Startups** | **No download needed.** Loads from disk. | **Full download required every time.** | **This Project (by a large margin)** |

---

## Alternative Strategy: Pre-loading a Persistent Disk for Instant Startup

The `initContainer` pattern is a robust and flexible way to manage model data, but it still requires a one-time download per Persistent Volume Claim. For the absolute fastest startup time, you can pre-load a GCE Persistent Disk with the model data *before* using it in your cluster. This eliminates the initial download entirely.

### Pros and Cons

| Pros | Cons |
| :--- | :--- |
| **Fastest Possible Startup:** Pods start almost instantly, as there is zero download time. | **More Complex Setup:** The initial, one-time setup is significantly more involved. |
| **Decoupled Workflow:** Model preparation becomes a separate, offline infrastructure task. | **Manual Model Updates:** To update the model, you must repeat the entire process. |

### Detailed Workflow

#### Step 1: Create a Temporary VM and the Source Disk

First, create a GCE disk and a temporary VM in the same zone as your GKE cluster.

```bash
# Create the persistent disk that will hold the model
gcloud compute disks create vllm-model-source-disk \
    --size=50GB \
    --type=pd-standard \
    --zone=us-central1-a # IMPORTANT: Use the same zone as your GKE cluster

# Create a small, temporary VM to load data onto the disk
gcloud compute instances create model-loader-vm \
    --machine-type=e2-micro \
    --zone=us-central1-a

# Attach the disk to the temporary VM
gcloud compute instances attach-disk model-loader-vm \
    --disk=vllm-model-source-disk \
    --zone=us-central1-a
```

#### Step 2: Load the Model Data onto the Disk

SSH into the VM and copy the model files from GCS to the attached disk.

```bash
# SSH into the temporary VM
gcloud compute ssh model-loader-vm --zone=us-central1-a

# Inside the VM, format and mount the attached disk
sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/sdb
sudo mkdir -p /mnt/disks/model-cache
sudo mount -o discard,defaults /dev/sdb /mnt/disks/model-cache
sudo chmod a+w /mnt/disks/model-cache

# Download the model from GCS to the mounted disk
gcloud storage cp -r gs://ai-llm-models/hf/gemma-3-1b-it /mnt/disks/model-cache/

# Exit the VM
exit
```

#### Step 3: Detach the Disk and Clean Up the VM

Once the disk is populated, you no longer need the temporary VM.

```bash
# Detach the now-populated disk from the VM
gcloud compute instances detach-disk model-loader-vm \
    --disk=vllm-model-source-disk \
    --zone=us-central1-a

# Delete the temporary VM
gcloud compute instances delete model-loader-vm --zone=us-central1-a --quiet
```

#### Step 4: Create a Kubernetes PV and PVC

Create a `PersistentVolume` (PV) that explicitly points to your pre-loaded GCE disk. Then, create a `PersistentVolumeClaim` (PVC) that binds to that specific PV. This prevents Kubernetes from trying to dynamically provision a new, empty disk.

Create a new file, `preloaded-volume.yaml`:

```yaml
# preloaded-volume.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: vllm-model-cache-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  gcePersistentDisk:
    pdName: vllm-model-source-disk # <-- Points to your specific GCE disk
    fsType: ext4
  storageClassName: "" # An empty storage class prevents dynamic provisioning
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vllm-model-cache
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  volumeName: vllm-model-cache-pv # <-- Binds this claim to our specific PV
  storageClassName: "" # Must match the PV
```

Apply this manifest to your cluster:
```bash
# Note: Delete the old PVC first if it exists
kubectl delete pvc vllm-model-cache --ignore-not-found
kubectl apply -f preloaded-volume.yaml
```

#### Step 5: Update the Deployment

Finally, modify your `vllm-deployment.yaml` to remove the `initContainers` section entirely, as it is no longer needed.

```yaml
# vllm-deployment.yaml (modified)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-gemma-1b
  # ...
spec:
  # ...
  template:
    metadata:
      # ...
    spec:
      serviceAccountName: vllm-sa
      # NO initContainers section needed anymore!
      containers:
      - name: vllm-container
        image: vllm/vllm-openai:latest
        env:
        - name: LD_LIBRARY_PATH
          value: "/usr/local/nvidia/lib64:/usr/local/cuda/lib64"
        command: ["python", "-m", "vllm.entrypoints.openai.api_server"]
        args:
          - "--model=/models/gemma-3-1b-it"
          - "--max-model-len=4096"
        # ...
        volumeMounts:
        - name: model-cache-volume
          mountPath: /models
      volumes:
      - name: model-cache-volume
        persistentVolumeClaim:
          claimName: vllm-model-cache
      # ...
```

After applying the updated deployment, the vLLM pod will start and find the model data already present on the persistent disk, achieving the fastest possible startup time.

## Optional: Optimizing for Cost by Scaling to Zero

After you've successfully deployed your model, your GPU node pool will run 24/7, which can be expensive. The following instructions show you how to configure your cluster to automatically scale your expensive GPU node pool down to **zero nodes** when it's not in use.

### GKE Autopilot
If you deployed your model on an **Autopilot** cluster, this behavior is **automatic**. You do not need to perform any configuration.

When you are finished with your workload, you simply delete the Deployment. Autopilot detects that no pods are requesting GPUs and will automatically remove the GPU nodes to save costs.

### GKE Standard
On a GKE Standard cluster, you must configure the Cluster Autoscaler and use taints and tolerations.

### 1. Ensure a Default Node Pool Exists

The cluster needs a non-GPU node pool to run system components when the GPU pool is scaled to zero. If you don't have one, create it.

```bash
# Skip this if you already have a non-GPU node pool
gcloud container node-pools create default-pool \
  --cluster=seans-local-model \
  --region=us-central1 \
  --machine-type=e2-medium \
  --num-nodes=1
```

### 2. Update Your GPU Node Pool for Autoscaling

Modify your existing `gpu-pool` to enable autoscaling and add a taint. The taint prevents system pods from running on your GPU nodes, which allows the pool to become completely empty.

```bash
gcloud container node-pools update gpu-pool \
  --cluster=seans-local-model \
  --region=us-central1 \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=5 \
  --node-taints=nvidia.com/gpu=present:NoSchedule
```

### 3. Update Your Deployment for the Taint

Edit your `vllm-deployment.yaml` file to add a `tolerations` block so your pods can run on the tainted GPU nodes.

```yaml
# vllm-deployment.yaml
# ...
spec:
  template:
    # ...
    spec:
      serviceAccountName: vllm-sa
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: vllm-container
        # ...
```

Then, apply the change.

```bash
kubectl apply -f vllm-deployment.yaml
```

### 4. Trigger the Scale-Down
When you are finished, delete the deployment to trigger the scale-down.

```bash
kubectl delete -f vllm-deployment.yaml
```
