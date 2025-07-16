# HPA AI Inference Server using NVidia GPU Metrics

This exercise shows how to set up the infrastructure to automatically
scale an AI inference server, using custom metrics (GPU metrics). This
exercise requires Managed Prometheus service, which is automatically
enabled for GKE clusters >= v1.27. We assume you already have the vLLM
AI inference server running from this [exercise](../README.md), in the
parent directory.

## I. Collect Metrics into Managed Prometheus

Ensure the necessary metrics are being collected. We use a
`ClusterPodMonitoring` custom resource, along with monitoring rules.

### Collect NVidia GPU metrics

The `ClusterPodMonitoring` custom resource will scrape NVidia GPU metrics
into GKE Prometheus. This workload *must* be cluster-scoped, because
the pods that it scrapes are in a protected namespace --
`gke-managed-system`. These scraped pods are from an NVidia metrics
exporter workload.

```
# First, verify the nvidia metrics exporter is running.
$ kubectl get all --namespace gke-managed-system
NAME                      READY   STATUS    RESTARTS   AGE
pod/dcgm-exporter-5vdk9   1/1     Running   0          8d

NAME                           DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/dcgm-exporter   1         1         1       1            1           <none>          8d
```

Next, deploy the `ClusterPodMonitoring` resource. Notice that this resource
translates the nvidia metrics names into lower-case. This is necessary
to overcome a metrics bug.

```
$ kubectl apply -f ./gpu-pod-monitoring.yaml
$ kubectl apply -f ./gpu-rules.yaml
```

Validate the NVIDIA GPU metrics are being collected into GKE
Prometheus by viewing the `Metrics explorer` in the gcloud
console. Attempt to filter by `dcgm`, and you should be able
to see the following metric: `dcgm_fi_dev_gpu_util`. This metric
represents the percentage of time over the last sample period
(typically one second) that one or more compute kernels were
actively executing on the GPU. In simpler terms, it tells you
how busy the GPU's processing cores were. A value of 100 means
the GPU was constantly running compute tasks during the last
interval, while a value of 0 means it was idle. It is one of
the most common metrics for determining if a workload is
"GPU-bound" or if GPUs are being underutilized.

## III. Stackdriver Adapter for viewing metrics in GKE Prometheus

### Deploy StackDriver Adapter

The metric stackdriver adapter allows the Horizontal Pod Autoscaler to
view/retrieve the previously collected metrics in Prometheus. This adapter
does *not* have permissions (yet) to view metrics in Prometheus (see
next step).

```
$ kubectl apply -f ./stack-driver-adapter.yaml
```

Verify the stack driver adapter workloads are deployed in the
`custom-metrics` namespace.

```
$ kubectl get all --namespace custom-metrics
NAME                                                      READY   STATUS    RESTARTS          AGE
pod/custom-metrics-stackdriver-adapter-658f5968bd-nkmk2   1/1     Running   281 (6d23h ago)   7d23h

NAME                                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/custom-metrics-stackdriver-adapter   ClusterIP   34.118.227.38   <none>        443/TCP   8d

NAME                                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/custom-metrics-stackdriver-adapter   1/1     1            1           8d

NAME                                                            DESIRED   CURRENT   READY   AGE
replicaset.apps/custom-metrics-stackdriver-adapter-658f5968bd   1         1         1       8d
```

### Use Workload Identity to give permission to view metrics

Assuming the project is `seans-devel`, enable workload identity by creating
a gcloud service account `metrics-adapte-gsa` to give workloads permissons
to view metrics within gcloud:

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

### Verify StackDriver adapter is working

```
# First, discover the name of the stack driver adapter pod.
$ kubectl get po --namespace custom-metrics
NAME                                                  READY   STATUS    RESTARTS          AGE
custom-metrics-stackdriver-adapter-658f5968bd-nkmk2   1/1     Running   281 (6d23h ago)   7d23h

# Verify the stackdriver adapter now works, and has no permissions issues
$ kubectl logs -f po/custom-metrics-stackdriver-adapter-658f5968bd-nkmk2 --namespace custom-metrics

I0715 18:34:57.743218       1 filter_builder.go:258] Query with filter(s): "metric.labels.pod = \"vllm-gemma-deployment-69bc477d85-qmg2v\" AND metric.type = \"prometheus.googleapis.com/vllm:num_requests_running/gauge\" AND resource.labels.cluster = \"seans-gpu-hpa\" AND resource.labels.location = \"us-central1\" AND resource.labels.namespace = \"default\" AND resource.labels.project_id = \"seans-devel\" AND resource.type = \"prometheus_target\""
```

## IV. Deploy Horizontal Pod Autoscaler

### Deploy the HPA

Create the horizontal pod autoscaler (HPA), to scale the AI inference
server. This HPA targets the AI inference `Deployment` named
`vllm-gemma-deployment`, with a pod replica range of 1 to 5 pods.
The target metric is `prometheus.googleapis.com|vllm:num_requests_running|gauge`,
which keeps track of the number of concurrent requests running
withing the pods of the vLLM deployment. If the average of this metric
exceeds 4, then a scale event happens.

```
$ kubectl apply -f ./horizontal-pod-autoscaler.yaml
```

### Verify the HPA

Validate the metric the HPA is using to scale. From the targeted metric,
the `prometheus.googleapis.com` part means the metric lives in GKE
Prometheus, while the `vllm:num_requests_running` is the metric
from the `vllm` AI inference server named `num_requests_running`. This
metric is of type `gauge`. Also, check the `ValidMetricFound` event.

```
$ kubectl describe hpa/gemma-server-hpa
Name:                                                                   gemma-server-hpa
Namespace:                                                              default
Labels:                                                                 <none>
Annotations:                                                            <none>
CreationTimestamp:                                                      Tue, 08 Jul 2025 18:15:27 +0000
Reference:                                                              Deployment/vllm-gemma-deployment
Metrics:                                                                ( current / target )
  "prometheus.googleapis.com|vllm:num_requests_running|gauge" on pods:  0 / 4
Min replicas:                                                           1
Max replicas:                                                           5
Behavior:
  Scale Up:
    Stabilization Window: 0 seconds
    Select Policy: Max
    Policies:
      - Type: Pods     Value: 4    Period: 15 seconds
      - Type: Percent  Value: 100  Period: 15 seconds
  Scale Down:
    Stabilization Window: 30 seconds
    Select Policy: Max
    Policies:
      - Type: Percent  Value: 100  Period: 15 seconds
Deployment pods:       1 current / 1 desired
Conditions:
  Type            Status  Reason            Message
  ----            ------  ------            -------
  AbleToScale     True    ReadyForNewScale  recommended size matches current size
  ScalingActive   True    ValidMetricFound  the HPA was able to successfully calculate a replica count from pods metric prometheus.googleapis.com|vllm:num_requests_running|gauge
  ScalingLimited  True    TooFewReplicas    the desired replica count is less than the minimum replica count
Events:           <none>
```

## V. Test

Forward requests sent to local port `8081` to `llm-service` service
listening on port `8081` within the cluster.

```
$ kubectl port-forward service/llm-service 8081:8081
Forwarding from 127.0.0.1:8081 -> 8081
Forwarding from [::1]:8081 -> 8081
...
```

Within another terminal run AI requests in a loop to load
the GPU, and see if the HPA is scaling the inference deployment.

```
$ ./request-looper.sh
Starting request loop...
  PORT: 8081
  MODEL: google/gemma-3-1b-it
  CONTENT: Explain Quantum Computing in simple terms.
Press Ctrl+C to stop.
----------------------------------------
Sending request at Tue Jul 15 10:26:21 PM UTC 2025
----------------------------------------
Sending request at Tue Jul 15 10:26:22 PM UTC 2025
----------------------------------------
Sending request at Tue Jul 15 10:26:23 PM UTC 2025
...
```

Check the HPA

```
$ kubectl describe hpa/gemma-serve-hpa
...
Events:
  Type    Reason             Age                    From                       Message
  ----    ------             ----                   ----                       -------
  Normal  SuccessfulRescale  2m50s (x3 over 6d23h)  horizontal-pod-autoscaler  New size: 3; reason: pods metric prometheus.googleapis.com|vllm:num
```

The following shows the deployment has scaled from 1 to 3 replicas.

```
$ kubectl get deploy/vllm-gemma-deployment
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
vllm-gemma-deployment   3/3     3            1           8d
```


## VI. Cleanup
