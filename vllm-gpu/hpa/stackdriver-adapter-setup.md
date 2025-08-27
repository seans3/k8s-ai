# Appendix: Configuring the Stackdriver Adapter for HPA

This document provides the detailed steps for deploying the Custom Metrics Stackdriver Adapter and configuring it with the necessary permissions to allow the Horizontal Pod Autoscaler (HPA) to access custom metrics from GKE's Managed Service for Prometheus.

This is a prerequisite for both server-based and GPU-based autoscaling.

---

### 1. Deploy the Stackdriver Adapter

The adapter runs in its own namespace, `custom-metrics`, and acts as a bridge between the HPA controller and the Google Cloud Monitoring API.

**Apply the manifest:**
This command creates the `custom-metrics` namespace, the adapter's Deployment, Service, and all the necessary RBAC (Role-Based Access Control) resources.

```bash
kubectl apply -f ./stack-driver-adapter.yaml
```

**Verify the deployment:**
Check that the adapter's pod is running successfully in the `custom-metrics` namespace.

```bash
kubectl get pods -n custom-metrics
```
You should see a pod named `custom-metrics-stackdriver-adapter-...` with a `STATUS` of `Running`.

---

### 2. Grant Permissions with Workload Identity

To securely grant the adapter permission to read metrics from your Google Cloud project, you will use **Workload Identity**, which is the recommended way to allow Kubernetes workloads to access Google Cloud services.

This process involves linking a Kubernetes Service Account (`custom-metrics-stackdriver-adapter`) to a Google Service Account.

**Note:** In the commands below, replace `seans-devel` with your actual Google Cloud Project ID.

```bash
# Set your project ID as a variable for convenience
export PROJECT_ID="seans-devel"

# 1. Create a dedicated Google Service Account (GSA) for the adapter
gcloud iam service-accounts create metrics-adapter-gsa \
  --project=${PROJECT_ID} \
  --display-name="Custom Metrics Stackdriver Adapter GSA"

# 2. Grant the GSA the "Monitoring Viewer" role
# This gives it the necessary permissions to read metrics data from the project.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:metrics-adapter-gsa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/monitoring.viewer"

# 3. Create an IAM policy binding between the GSA and the Kubernetes Service Account (KSA)
# This allows the KSA to impersonate the GSA.
gcloud iam service-accounts add-iam-policy-binding \
  metrics-adapter-gsa@${PROJECT_ID}.iam.gserviceaccount.com \
  --project=${PROJECT_ID} \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[custom-metrics/custom-metrics-stackdriver-adapter]"

# 4. Annotate the Kubernetes Service Account
# This final step completes the link, telling GKE that the KSA is authorized to act as the GSA.
kubectl annotate serviceaccount \
  custom-metrics-stackdriver-adapter \
  --namespace custom-metrics \
  iam.gke.io/gcp-service-account=metrics-adapter-gsa@${PROJECT_ID}.iam.gserviceaccount.com
```

---

### 3. Verify the Adapter's Functionality

Finally, check the logs of the adapter pod to confirm that it has successfully authenticated and is ready to serve metrics to the HPA.

```bash
# Find the full name of the adapter pod
ADAPTER_POD=$(kubectl get po -n custom-metrics -l k8s-app=custom-metrics-stackdriver-adapter -o jsonpath='{.items[0].metadata.name}')

# Stream the logs
kubectl logs -f "po/${ADAPTER_POD}" --namespace custom-metrics
```

After a few moments, you should see log entries indicating that the adapter is processing metric queries (even if there are no HPAs yet). The absence of permission-related errors is a strong indicator of a successful setup.
