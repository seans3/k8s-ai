# Serving Gemma with JetStream and TPUs on GKE Autopilot

This guide summarizes the steps to deploy and serve a Gemma large language model using JetStream on Google Kubernetes Engine (GKE) Autopilot mode, leveraging TPUs for inference.

Before proceeding, ensure you have completed all steps outlined in the [Prerequisites Guide](./prerequisites.md).

## I. Set Up Google Cloud and GKE Resources

1.  **Create GKE Autopilot Cluster with Workload Identity Enabled:**
    GKE Autopilot simplifies cluster management. When you request TPU resources, Autopilot provisions them. We enable Workload Identity for secure access to Google Cloud services.
    ```bash
    gcloud container clusters create-auto $CLUSTER_NAME \
        --project=$PROJECT_ID \
        --region=$REGION \
        --release-channel=rapid \
        --workload-pool=${PROJECT_ID}.svc.id.goog # Enable Workload Identity
    ```
    * Cluster creation can take several minutes.
    * The `$PROJECT_ID`, `$CLUSTER_NAME`, and `$REGION` variables are from `prerequisites.md`.

2.  **Get Cluster Credentials:**
    Configure `kubectl` to communicate with your new cluster:
    ```bash
    gcloud container clusters get-credentials $CLUSTER_NAME \
        --region=$REGION \
        --project=$PROJECT_ID
    ```

3.  **Create Kubernetes Secret for Kaggle Credentials:**
    This secret stores your Kaggle username and API key for model download.
    ```bash
    kubectl create secret generic kaggle-creds \
        --from-literal=username=${KAGGLE_USERNAME} \
        --from-literal=key=${KAGGLE_KEY} \
        --namespace=${K8S_NAMESPACE}
    ```

4.  **Configure Workload Identity Federation:**
    This allows Kubernetes Service Accounts (KSAs) to impersonate Google Service Accounts (GSAs), providing secure, keyless access to Google Cloud services.

    a.  **Create a Google Service Account (GSA):** This GSA will be used by your GKE workloads.
        ```bash
        gcloud iam service-accounts create ${GSA_NAME} \
            --project=${PROJECT_ID} \
            --display-name="JetStream GKE Service Account"
        ```

    b.  **Grant IAM Roles to the GSA:** Grant the GSA necessary permissions, for example, to access GCS for models.
        ```bash
        # Permission to read/write models and tokenizers in GCS
        gsutil iam ch serviceAccount:${GSA_NAME}@${PROJECT_ID}[.iam.gserviceaccount.com](https://www.google.com/search?q=.iam.gserviceaccount.com):objectAdmin gs://${MODEL_GCS_BUCKET_NAME}

        # If the GSA needs other permissions (e.g., for specific APIs), grant them here:
        # gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        #     --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}[.iam.gserviceaccount.com](https://www.google.com/search?q=.iam.gserviceaccount.com)" \
        #     --role="<another_required_role>"
        ```

    c.  **Create a Kubernetes Service Account (KSA):**
        ```bash
        kubectl create serviceaccount ${KSA_NAME} --namespace ${K8S_NAMESPACE}
        ```

    d.  **Allow the KSA to Impersonate the GSA:**
        Bind the `roles/iam.workloadIdentityUser` role to the GSA for the KSA.
        ```bash
        gcloud iam service-accounts add-iam-policy-binding ${GSA_NAME}@${PROJECT_ID}[.iam.gserviceaccount.com](https://www.google.com/search?q=.iam.gserviceaccount.com) \
            --role="roles/iam.workloadIdentityUser" \
            --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]" \
            --project=${PROJECT_ID}
        ```

    e.  **Annotate the KSA:** Link the KSA with the GSA.
        ```bash
        kubectl annotate serviceaccount ${KSA_NAME} \
            --namespace ${K8S_NAMESPACE} \
            iam.gke.io/gcp-service-account=${GSA_NAME}@${PROJECT_ID}[.iam.gserviceaccount.com](https://www.google.com/search?q=.iam.gserviceaccount.com)
        ```
        Your Kubernetes workloads (Jobs, Deployments) will now use `serviceAccountName: ${KSA_NAME}` in their pod specs to assume the GSA's permissions.

## II. Prepare and Convert Gemma Model for JetStream

JetStream requires models in a specific checkpoint format (often MaxText format) stored in GCS. A Kubernetes Job typically handles downloading, converting, and uploading Gemma.

1.  **Define the Model Conversion Kubernetes Job YAML:**
    Create `model-conversion-job.yaml`.
    * **Key configurations:**
        * `apiVersion: batch/v1`, `kind: Job`
        * `spec.template.spec.serviceAccountName: ${KSA_NAME}` (to use Workload Identity for GCS access).
        * `spec.template.spec.restartPolicy: Never`
        * `spec.template.spec.containers`:
            * `name`: (e.g., `model-converter`)
            * `image`: (e.g., `us-docker.pkg.dev/deeplearning-platform-release/gemma-maxtext-convert:latest`)
            * `env`: `KAGGLE_USERNAME` & `KAGGLE_KEY` from `kaggle-creds` secret, `MODEL_VARIANT`, `GCS_OUTPUT_PATH` (to `$CONVERTED_MODEL_GCS_PATH`), `TOKENIZER_GCS_PATH`.
            * `args`/`command`: Script to download from Kaggle, convert, and upload to GCS.
            * `resources` and `annotations` for TPUs, similar to those described in `prerequisites.md` if conversion is TPU accelerated.
    * *Refer to the specific tutorial for the exact Job YAML structure, image, and conversion script arguments.*

2.  **Apply the Model Conversion Job Manifest:**
    ```bash
    kubectl apply -f model-conversion-job.yaml --namespace ${K8S_NAMESPACE}
    ```

3.  **Monitor the Job:**
    ```bash
    kubectl get jobs -n ${K8S_NAMESPACE} -w
    kubectl logs job/<job-name-from-yaml> -n ${K8S_NAMESPACE} -f
    ```
    Ensure the Job completes and converted artifacts are in `$CONVERTED_MODEL_GCS_PATH`.

## III. Deploy JetStream Server

With the model converted, deploy the JetStream server.

1.  **Define the JetStream Kubernetes Deployment YAML:**
    Create `jetstream-deployment.yaml`.
    * **Key configurations:**
        * `apiVersion: apps/v1`, `kind: Deployment`
        * `spec.template.spec.serviceAccountName: ${KSA_NAME}` (for GCS access via Workload Identity).
        * `spec.template.spec.containers`:
            * `name`: (e.g., `jetstream-server`)
            * `image`: (e.g., `us-docker.pkg.dev/gke-release/jetstream-maxtext/gemma:latest`)
            * `args`:
                * `--model_name=$MODEL_NAME`
                * `--tokenizer_path=$TOKENIZER_GCS_PATH`
                * `--checkpoint_path=$CONVERTED_MODEL_GCS_PATH`
                * `--platform=tpu`, `--http_port=9000`
            * `ports.containerPort`: (e.g., 9000).
            * `resources` and `annotations` for serving TPUs (e.g., `google.com/tpu: "YOUR_SERVING_TPU_COUNT"`, `tpu.googleapis.com/podslice-accelerator-type: "tpu-v5-lite-podslice"`, `tpu.googleapis.com/podslice-topology: "YOUR_SERVING_TOPOLOGY"`).
        * *Note: The JetStream server pod now uses Workload Identity to access GCS, so it doesn't directly need the `kaggle-creds` secret if all assets are already in GCS. If the server's image or its startup logic still tries to download some assets (like a tokenizer not pre-processed to GCS) from Kaggle/HuggingFace directly, then the `kaggle-creds` secret and appropriate env var setup from that secret would be needed in this deployment too.* The tutorial typically has the conversion job prepare everything on GCS.

2.  **Apply the Deployment Manifest:**
    ```bash
    kubectl apply -f jetstream-deployment.yaml --namespace ${K8S_NAMESPACE}
    ```

3.  **Monitor Deployment Status:**
    ```bash
    kubectl get pods -n ${K8S_NAMESPACE} -l app=jetstream-gemma-server -w # Adjust label
    kubectl wait --for=condition=Available --timeout=1200s deployment/jetstream-gemma-server -n ${K8S_NAMESPACE} # Adjust name
    ```

4.  **View Logs:**
    ```bash
    kubectl logs -n ${K8S_NAMESPACE} -f -l app=jetstream-gemma-server # Adjust label
    ```

## IV. Expose and Test the JetStream Server

1.  **Define Kubernetes Service YAML (ClusterIP):**
    Create `jetstream-service.yaml`.
    * **Key configurations:**
        * `spec.type: ClusterIP`
        * `spec.selector`: Matches JetStream deployment pod labels.
        * `spec.ports.port` and `targetPort` (e.g., 9000).

2.  **Apply the Service Manifest:**
    ```bash
    kubectl apply -f jetstream-service.yaml --namespace ${K8S_NAMESPACE}
    ```

3.  **Accessing the Service (via Port Forwarding):**
    ```bash
    kubectl port-forward service/jetstream-gemma-svc -n ${K8S_NAMESPACE} 8080:9000
    ```

4.  **Interact with the Model using `curl`:**
    Assuming JetStream exposes an OpenAI-compatible HTTP endpoint:
    ```bash
    curl http://localhost:8080/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$MODEL_NAME"'",
            "messages": [
                {
                    "role": "user",
                    "content": "What are the main components of a Transformer model?"
                }
            ],
            "temperature": 0.7,
            "top_p": 1.0,
            "n": 1,
            "max_tokens": 256
        }'
    ```

## V. Observe and Troubleshoot

* Use `kubectl logs` and `kubectl describe pod/job -n ${K8S_NAMESPACE}`.
* Monitor TPU and GCS via Cloud Monitoring.

## VI. Clean Up

1.  **Delete Kubernetes Resources:**
    ```bash
    kubectl delete service jetstream-gemma-svc -n ${K8S_NAMESPACE}
    kubectl delete deployment jetstream-gemma-server -n ${K8S_NAMESPACE}
    kubectl delete job <your-conversion-job-name> -n ${K8S_NAMESPACE} # Adjust job name
    kubectl delete secret kaggle-creds -n ${K8S_NAMESPACE}
    kubectl delete serviceaccount ${KSA_NAME} -n ${K8S_NAMESPACE}
    ```

2.  **Remove IAM Bindings and Delete GSA:**
    ```bash
    gcloud iam service-accounts remove-iam-policy-binding ${GSA_NAME}@${PROJECT_ID}[.iam.gserviceaccount.com](https://www.google.com/search?q=.iam.gserviceaccount.com) \
        --role="roles/iam.workloadIdentityUser" \
        --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]" \
        --project=${PROJECT_ID}

    # Remove GCS bucket binding (adjust bucket name if different)
    gsutil iam ch -d serviceAccount:${GSA_NAME}@${PROJECT_ID}[.iam.gserviceaccount.com](https://www.google.com/search?q=.iam.gserviceaccount.com):objectAdmin gs://${MODEL_GCS_BUCKET_NAME}

    # Delete GSA
    gcloud iam service-accounts delete ${GSA_NAME}@${PROJECT_ID}[.iam.gserviceaccount.com](https://www.google.com/search?q=.iam.gserviceaccount.com) --project=${PROJECT_ID}
    ```

3.  **Delete GCS Bucket Content (Optional):**
    ```bash
    gsutil -m rm -r $CONVERTED_MODEL_GCS_PATH
    gsutil -m rm -r $TOKENIZER_GCS_PATH
    gsutil rb $MODEL_GCS_BUCKET
    ```

4.  **Delete the GKE Autopilot Cluster:**
    ```bash
    gcloud container clusters delete $CLUSTER_NAME \
        --region=$REGION \
        --project=$PROJECT_ID
    ```

This summary provides a comprehensive overview. Always refer to the exact commands, YAML configurations, JetStream arguments, and TPU request formats specified in the official Google Cloud documentation link you provided.
