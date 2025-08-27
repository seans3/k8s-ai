# Serving Gemma with JetStream and TPUs on GKE Autopilot

This guide provides a comprehensive walkthrough for deploying and serving the Gemma large language model using JetStream on the Google Kubernetes Engine (GKE) in Autopilot mode, with TPUs for hardware acceleration.

## Overview

The process involves these key stages:
1.  **Prerequisites**: Setting up your Google Cloud environment, tools, and local configuration.
2.  **Infrastructure Setup**: Creating a GKE Autopilot cluster and configuring secure access to Google Cloud services using Workload Identity.
3.  **Model Preparation**: Converting the Gemma model to the JetStream-compatible MaxText format and uploading it to Google Cloud Storage (GCS).
4.  **Deployment**: Deploying the JetStream server on your GKE cluster.
5.  **Testing**: Verifying the deployment by sending inference requests to the model.
6.  **Cleanup**: Deleting the resources to avoid incurring further costs.

---

## 1. Prerequisites

Before you begin, complete all the steps in the [Prerequisites Guide](./prerequisites.md). This guide will help you:
*   Set up your Google Cloud project and enable the necessary APIs.
*   Install and configure the `gcloud` CLI and `kubectl`.
*   Obtain Kaggle API credentials to download the Gemma model.
*   Define all the necessary environment variables for the subsequent steps. See `prerequisites.md` for a description of each variable.

---

## 2. GKE and Workload Identity Setup

In this section, we will create a GKE Autopilot cluster and configure Workload Identity, which provides secure, keyless access to Google Cloud services from your GKE workloads.

The commands in this section use the environment variables you defined in the `prerequisites.md` file. These variables streamline the setup process by providing consistent names for resources like your cluster, service accounts, and GCS bucket.

### a. Create a GKE Autopilot Cluster

GKE Autopilot simplifies cluster management by automatically provisioning and managing the underlying infrastructure, including TPU resources when requested.

```bash
gcloud container clusters create-auto $CLUSTER_NAME \
    --project=$PROJECT_ID \
    --region=$REGION \
    --release-channel=rapid \
    --workload-pool=${PROJECT_ID}.svc.id.goog
```
*   **Note**: Cluster creation can take several minutes. The `${PROJECT_ID}.svc.id.goog` flag enables Workload Identity.

### b. Get Cluster Credentials

Configure `kubectl` to communicate with your new cluster:
```bash
gcloud container clusters get-credentials $CLUSTER_NAME \
    --region=$REGION \
    --project=$PROJECT_ID
```

### c. Create a Kubernetes Secret for Kaggle Credentials

This secret securely stores your Kaggle API credentials, which are required to download the Gemma model.
```bash
kubectl create secret generic kaggle-creds \
    --from-literal=username=${KAGGLE_USERNAME} \
    --from-literal=key=${KAGGLE_KEY} \
    --namespace=${K8S_NAMESPACE}
```

### d. Configure Workload Identity

Workload Identity allows a Kubernetes Service Account (KSA) to impersonate a Google Service Account (GSA), inheriting its permissions.

1.  **Create a Google Service Account (GSA)**:
    ```bash
    gcloud iam service-accounts create ${GSA_NAME} \
        --project=${PROJECT_ID} \
        --display-name="JetStream GKE Service Account"
    ```

2.  **Grant GCS Permissions to the GSA**:
    The GSA needs permissions to read and write to the GCS bucket where the model will be stored.
    ```bash
    gsutil iam ch serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com:objectAdmin gs://${MODEL_GCS_BUCKET_NAME}
    ```

3.  **Create a Kubernetes Service Account (KSA)**:
    ```bash
    kubectl create serviceaccount ${KSA_NAME} --namespace ${K8S_NAMESPACE}
    ```

4.  **Bind the KSA to the GSA**:
    This binding allows the KSA to act as the GSA.
    ```bash
    gcloud iam service-accounts add-iam-policy-binding ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
        --role="roles/iam.workloadIdentityUser" \
        --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]" \
        --project=${PROJECT_ID}
    ```

5.  **Annotate the KSA**:
    This annotation links the KSA to the GSA within GKE.
    ```bash
    kubectl annotate serviceaccount ${KSA_NAME} \
        --namespace ${K8S_NAMESPACE} \
        iam.gke.io/gcp-service-account=${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
    ```
With this configuration, any Kubernetes pod running with `serviceAccountName: ${KSA_NAME}` will automatically authenticate with Google Cloud services using the GSA's permissions.

---

## 3. Prepare and Convert the Gemma Model

JetStream requires the Gemma model to be in a specific checkpoint format (MaxText) and stored in GCS. We will use a Kubernetes Job to perform this conversion.

The `gemma-tpu-job.yaml` file defines this job. It uses the `kaggle-creds` secret to download the model and the `${KSA_NAME}` service account (configured with Workload Identity) to upload the converted model to your GCS bucket. The job is configured to use the `${MODEL_NAME}` and other environment variables to determine which model to convert and where to store it.

### a. Apply the Model Conversion Job

The following command uses `envsubst` to substitute the environment variables (like `${KSA_NAME}` and `${MODEL_NAME}`) in the YAML file before applying it.

*   **Note**: If you don't have `envsubst`, you can install it with `sudo apt-get install gettext-base` on Debian/Ubuntu or `brew install gettext` on macOS.

```bash
envsubst < gemma-tpu-job.yaml | kubectl apply -f -
```

### b. Monitor the Job

Track the job's progress and ensure it completes successfully.
```bash
# Watch the job status
kubectl get jobs -n ${K8S_NAMESPACE} -w

# View the logs of the conversion pod
kubectl logs job/gemma-tpu-job -n ${K8S_NAMESPACE} -f
```
Once the job is complete, the converted model and tokenizer will be available in your GCS bucket at `$CONVERTED_MODEL_GCS_PATH` and `$TOKENIZER_GCS_PATH`.

---

## 4. Deploy the JetStream Server

Now that the model is ready, we can deploy the JetStream server.

The `jetstream-deployment.yaml` file defines the deployment for the JetStream server. It uses the `${KSA_NAME}` service account to access the converted model in your GCS bucket. The deployment arguments are configured using environment variables like `${MODEL_NAME}`, `${CONVERTED_MODEL_GCS_PATH}`, and `${TOKENIZER_GCS_PATH}` to ensure the server loads the correct model and tokenizer.

### a. Apply the Deployment Manifest

This command also uses `envsubst` to ensure that variables like the service account name and GCS paths are correctly configured in the deployment.

```bash
envsubst < jetstream-deployment.yaml | kubectl apply -f -
```

### b. Monitor the Deployment

Verify that the JetStream server pods start and become ready.
```bash
# Watch the pod status (adjust the label if needed)
kubectl get pods -n ${K8S_NAMESPACE} -l app=jetstream-gemma-server -w

# Wait for the deployment to be fully available
kubectl wait --for=condition=Available --timeout=1200s deployment/jetstream-gemma-server -n ${K8S_NAMESPACE}
```

### c. View Logs

Check the logs to ensure the server started correctly.
```bash
kubectl logs -n ${K8S_NAMESPACE} -f -l app=jetstream-gemma-server
```

---

## 5. Expose and Test the Service

To interact with the JetStream server, we will expose it within the cluster using a ClusterIP service and use port-forwarding for local testing.

### a. Create the Service

Apply the service manifest to expose the JetStream server within the cluster.

```bash
envsubst < jetstream-service.yaml | kubectl apply -f -
```

### b. Access the Service via Port Forwarding

Forward a local port to the service port:
```bash
kubectl port-forward service/jetstream-gemma-svc -n ${K8S_NAMESPACE} 8080:9000
```

### c. Send an Inference Request

In a new terminal, use `curl` to interact with the model:
```bash
curl --request POST \
--header "Content-type: application/json" \
-s \
localhost:8080/generate \
--data \
'{ 
    "prompt": "What are the top 5 programming languages",
    "max_tokens": 200
}'
```

---

## 6. Troubleshooting

*   **Pod Errors**: Use `kubectl describe pod/<pod-name> -n ${K8S_NAMESPACE}` to investigate issues with pods.
*   **Job Failures**: Use `kubectl logs job/<job-name> -n ${K8S_NAMESPACE}` to debug the model conversion job.
*   **Cloud Monitoring**: Monitor TPU and GCS usage in the Google Cloud Console for performance insights.

---

## 7. Cleanup

To avoid ongoing charges, delete the resources you created.

### a. Delete Kubernetes Resources
```bash
kubectl delete service jetstream-gemma-svc -n ${K8S_NAMESPACE}
kubectl delete deployment jetstream-gemma-server -n ${K8S_NAMESPACE}
kubectl delete job gemma-tpu-job -n ${K8S_NAMESPACE}
kubectl delete secret kaggle-creds -n ${K8S_NAMESPACE}
kubectl delete serviceaccount ${KSA_NAME} -n ${K8S_NAMESPACE}
```

### b. Delete IAM and GSA Resources
```bash
# Remove IAM policy binding
gcloud iam service-accounts remove-iam-policy-binding ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]" \
    --project=${PROJECT_ID}

# Remove GCS bucket binding
gsutil iam ch -d serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com:objectAdmin gs://${MODEL_GCS_BUCKET_NAME}

# Delete GSA
gcloud iam service-accounts delete ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --project=${PROJECT_ID}
```

### c. Delete GCS Bucket (Optional)
```bash
gsutil -m rm -r gs://${MODEL_GCS_BUCKET_NAME}
```

### d. Delete GKE Cluster
```bash
gcloud container clusters delete $CLUSTER_NAME \
    --region=$REGION \
    --project=${PROJECT_ID}
```