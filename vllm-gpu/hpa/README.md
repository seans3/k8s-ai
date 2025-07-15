# Horizontal Pod Autoscaling AI Inference Server

This exercise shows how to set up the infrastructure to automatically
scale an AI inference server, using custom metrics (either server
or GPU metrics). This exercise requires Managed Prometheus service,
which is automatically enabled for GKE clusters >= v1.27. We assume
you already have the vLLM AI inference server running from this
[exercise](../README.md), in the parent directory.

## I. Collect Metrics into Managed Prometheus

The first step is ensure the necessary metrics are being collected. We
use either a `ClusterPodMonitoring` or `PodMonitoring` (namespaced)
custom resource.

### A. Collect vLLM metrics

PodMonitoring custom resource

### B. Collect NVidia GPU metrics

ClusterPodMonitoring custom resource to scrape NVidia DCMG metric exporter

## II. Deploy Stackdriver Adapter

..so HPA can retrieve the previously collected metrics

### A. Use Workload Identity to give permission to view metrics

Assuming project is `seans-devel`, creating workload identity by creating
a gcloud service account `metrics-adapte-gsa` to give workloads permissons
to view metrics within gcloud is the following:

```
$ gcloud iam service-accounts create metrics-adapter-gsa \
--project=seans-devel \
--display-name="Metrics Adapter GSA"

$ gcloud projects add-iam-policy-binding seans-dev \
--member="serviceAccount:metrics-adapter-gsa@seans-devel.iam.gserviceaccount.com" \
--role="roles/monitoring.viewer"

$ gcloud iam service-accounts add-iam-policy-binding \
    metrics-adapter-gsa@seans-devel.iam.gserviceaccount.com \
    --project=seans-devel \
    --role="roles/iam.workloadIdentityUser" \
--member="serviceAccount:seans-devel.svc.id.goog[custom-metrics/custom-metrics-stackdriver-adapter]"

$ kubectl annotate serviceaccount \
    custom-metrics-stackdriver-adapter \
    --namespace custom-metrics \
    iam.gke.io/gcp-service-account=metrics-adapter-gsa@seans-devel.iam.gserviceaccount.com
```

## III. Deploy Horizontal Pod Autoscaler

## IV. Test

## V. Cleanup
