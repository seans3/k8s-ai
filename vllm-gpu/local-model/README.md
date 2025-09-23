# Deploying a vLLM Server with a GCS Bucket using the GCS CSI Driver

This document provides the steps to deploy a vLLM inference server on GKE, loading a model directly from a GCS bucket mounted as a volume using the GCS CSI Driver.

## Prerequisites

1.  A GKE cluster with a node pool that has GPUs.
2.  The GCS CSI Driver must be enabled on your GKE cluster. You can enable it with the following command:
    ```bash
    gcloud container clusters update CLUSTER_NAME --update-addons GcsFuseCsiDriver=ENABLED
    ```
3.  Workload Identity must be enabled on the cluster.
4.  `kubectl` configured to communicate with your GKE cluster.
5.  A GCS bucket containing the model files.

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
    This creates the service account in a declarative way from a manifest file.

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

### Step 2: Create the StorageClass, PersistentVolume and PersistentVolumeClaim

These resources tell Kubernetes how to connect to the GCS bucket.

1.  **Create the StorageClass:**
    ```bash
    kubectl apply -f ./storage-class.yaml
    ```
2.  **Create the PersistentVolume:**
    ```bash
    kubectl apply -f ./persistent-volume.yaml
    ```
3.  **Create the PersistentVolumeClaim:**
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

Check the status of the deployment and pods. The pod should start more quickly as it does not need to download the model.

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

This section documents the extensive troubleshooting process undertaken to debug issues with the GCS CSI driver on both GKE Autopilot and Standard clusters.

### 1. Initial Deployment on GKE Autopilot

*   **Objective:** Deploy the vLLM server using the GCS CSI driver on an Autopilot cluster.
*   **Initial Problem:** The pod remained in a `Pending` state. Events showed a `FailedScheduling` error because no existing nodes had the requested `nvidia-l4` GPU.
*   **Correction & New Issue:** Realized Autopilot needed time to provision a new GPU node. However, the provisioning then failed with a `FailedScaleUp` event, indicating a temporary "out of resources" stockout for L4 GPUs in the `us-central1-b` zone.
*   **Persistent Problem:** After a node was eventually provisioned, the pod became stuck in `ContainerCreating`. The key event was `Warning FailedAttachVolume... timed out waiting for external-attacher`. This pointed to an issue with the CSI driver's control plane components.

### 2. Debugging the CSI Driver on Autopilot

*   **Hypothesis 1: IAM Permissions:** We meticulously verified the entire Workload Identity chain:
    1.  The GCS bucket had the correct `roles/storage.objectViewer` binding for the Google Service Account (GSA).
    2.  The GSA had the correct `roles/iam.workloadIdentityUser` binding for the Kubernetes Service Account (KSA).
    3.  The KSA had the correct `iam.gke.io/gcp-service-account` annotation.
    *   **Conclusion:** All permissions were correctly configured.
*   **Hypothesis 2: CSI Driver Failure:** We investigated the CSI driver components.
    1.  The `gcsfusecsi-node-*` pods were running correctly on the node.
    2.  Logs from the node driver pods showed no errors.
    3.  A key discovery was made: the vLLM pod was missing the `gcsfuse-proxy` sidecar container, which is essential for the volume mount. This indicated the driver's mutating webhook was not working.
*   **Hypothesis 3: Webhook Interference:** A common cause for injection failure is conflicting webhooks.
    1.  We listed the `mutatingwebhookconfigurations` and identified the `warden-mutating` webhook, a mandatory security component on Autopilot, as a likely suspect.
    2.  An attempt to disable this webhook was blocked by GKE's managed resource limitations (`Forbidden`).
*   **Autopilot Conclusion:** We were at an impasse. The CSI driver was failing to inject its sidecar, likely due to an unavoidable conflict with a managed security feature on Autopilot.

### 3. Migrating to a GKE Standard Cluster

*   **Objective:** Move to a more flexible environment without the restrictive Autopilot webhooks.
*   **Action:** A new GKE Standard cluster was created, along with a dedicated L4 GPU node pool.
*   **New Problem:** Upon deploying the same manifests, the `FailedAttachVolume` error returned, but with a more specific and useful message: `rpc error: code = PermissionDenied desc = ... Caller does not have storage.objects.list access`.

### 4. Final Root Cause Analysis on GKE Standard

*   **Hypothesis: Incorrect Identity:** The `PermissionDenied` error proved that an identity was successfully reaching the GCS API but was being rejected. This pointed to the CSI driver using the wrong identity. The driver was using the **node's service account** instead of the pod's Workload Identity.
*   **Action 1: Grant Node Permissions:** We identified the node's service account (the Compute Engine default SA) and granted it the `storage.objectViewer` role on the GCS bucket.
    *   **Result:** The `PermissionDenied` error persisted, suggesting a more complex permissions issue with the default SA or that this was not the intended mechanism.
*   **Action 2: Force Pod Identity:** We added the `gke-gcs-fuse-csi: "true"` annotation to the pod specification. This is the documented method to force the CSI driver to use the pod's service account for the mount.
    *   **Result:** The `PermissionDenied` error still persisted.
*   **Definitive Test:** A diagnostic pod was deployed using the same KSA (`vllm-sa`). This pod successfully used Workload Identity to fetch a token from the GKE metadata server.
*   **Final Conclusion:** The diagnostic test proved that **Workload Identity is configured correctly**. The pod can acquire the correct credentials. The failure is definitively within the GCS CSI driver, which is not correctly using the pod's Workload Identity for the mount operation, even when explicitly instructed to do so via the annotation. This points to a bug or a subtle misconfiguration in the GKE CSI addon itself.