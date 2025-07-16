# Horizontal Pod Autoscaling AI Inference Server

This exercise shows how to set up the infrastructure to automatically
scale an AI inference server, using custom metrics (vllm server
metrics). This exercise requires Managed Prometheus service,
which is automatically enabled for GKE clusters >= v1.27. We assume
you already have the vLLM AI inference server running from this
[exercise](../README.md), in the parent directory.

## I. Verify vLLM AI Inference Server Metrics

Forward requests sent to local port `8081` to `llm-service` service
listening on port `8081` within the cluster.

```
$ kubectl port-forward service/llm-service 8081:8081
Forwarding from 127.0.0.1:8081 -> 8081
Forwarding from [::1]:8081 -> 8081
...
```

Next, in another terminal request the metrics endpoint for the vLLM inference
server by sending a `curl` request to local port `8081`, and filter the response
for the `num_requests_*` metrics.

```
$ curl -sS http://localhost:8081/metrics | grep num_requests_
# HELP vllm:num_requests_running Number of requests currently running on GPU.
# TYPE vllm:num_requests_running gauge
vllm:num_requests_running{model_name="google/gemma-3-1b-it"} 0.0
# HELP vllm:num_requests_swapped Number of requests swapped to CPU. DEPRECATED: KV cache offloading is not used in V1
# TYPE vllm:num_requests_swapped gauge
vllm:num_requests_swapped{model_name="google/gemma-3-1b-it"} 0.0
# HELP vllm:num_requests_waiting Number of requests waiting to be processed.
# TYPE vllm:num_requests_waiting gauge
vllm:num_requests_waiting{model_name="google/gemma-3-1b-it"} 0.0
```

## II. Collect Metrics into Managed Prometheus

Ensure the necessary metrics are being collected. We use a `PodMonitoring`
(namespaced) custom resource.

### Collect vLLM metrics

Create the `PodMonitoring` custom resource within the `default` namespace,
which sends metrics from pods with the `gemma-server` label to
GKE Prometheus. These metrics are configured to be found at the
`/metrics` endpoint of a server on port `8081`.

```
$ kubectl apply -f ./pod-monitoring.yaml
```

Verify the creation worked, especially checking the status condition
is `ConfigurationCreateSuccess`.

```
$ kubectl describe podmonitoring/gemma-pod-monitoring
Name:         gemma-pod-monitoring
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  monitoring.googleapis.com/v1
Kind:         PodMonitoring
Metadata:
  Creation Timestamp:  2025-07-07T19:41:21Z
  Generation:          2
  Resource Version:    1752013134641247019
  UID:                 fa94b4b2-6742-4b9b-aa64-b376d98c2124
Spec:
  Endpoints:
    Interval:  15s
    Path:      /metrics
    Port:      8081
  Selector:
    Match Labels:
      App:  gemma-server
  Target Labels:
    Metadata:
      pod
      container
      top_level_controller_name
      top_level_controller_type
Status:
  Conditions:
    Last Transition Time:  2025-07-07T19:41:21Z
    Last Update Time:      2025-07-08T22:18:54Z
    Status:                True
    Type:                  ConfigurationCreateSuccess
  Observed Generation:     2
Events:                    <none>
```

Also, verify the metrics are being collected into GKE Prometheus by
using the gcloud console `Metrics explorer` within the
`Observability Monitoring` section. Filter using the term `vllm`.

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
