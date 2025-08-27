# GKE AI Inference Gateway: Blue-Green Model Upgrades

This guide provides instructions for deploying a VLLM inference server on GKE using a blue-green deployment strategy. This approach enables zero-downtime updates and provides a safe, instantaneous rollback capability.

## Overview & Architecture

The blue-green deployment strategy is a high-availability release model that minimizes downtime and reduces risk. It involves maintaining two identical production environments, referred to as "blue" and "green."

-   **Blue Environment**: The live, production environment that receives all user traffic.
-   **Green Environment**: An identical, idle environment where the new version of the application is deployed and tested.

Once the green environment is verified, a router switches traffic from the blue to the green environment, making the new version live. The old blue environment is kept on standby for a quick rollback if needed.

This project implements this architecture on GKE using the following components:

1.  **Gateway (`gateway.yaml`)**: A single entry point for all inference requests, managed by GKE's Gateway controller. It provisions an external load balancer.

2.  **Blue/Green Deployments (`blue-vllm-deployment.yaml`, `green-vllm-deployment.yaml`)**: Two identical VLLM inference server deployments. Each runs in its own set of pods, allowing them to be updated and managed independently.

3.  **Blue/Green Services (`blue-vllm-service.yaml`, `green-vllm-service.yaml`)**: Each deployment is exposed internally by a `ClusterIP` Service, providing a stable network endpoint for the gateway to target.

4.  **HTTPRoute (`blue-route.yaml`, `green-route.yaml`)**: The core of the traffic-shifting mechanism. This resource defines rules that tell the Gateway how to distribute traffic between the blue and green services using weighted backends. By applying a different `HTTPRoute` manifest, we can instantly shift 100% of the traffic from one environment to the other.

## Deployment Instructions

### Prerequisites

1.  A configured Google Cloud project and authenticated `gcloud`/`kubectl` CLI. For a detailed guide on setting up your environment from scratch, see [SETUP.md](SETUP.md).
2.  A GKE Autopilot cluster.
3.  A Kubernetes secret named `hf-secret` in the `default` namespace containing your Hugging Face token. See [SETUP.md](SETUP.md) for instructions.
4.  Sufficient NVIDIA L4 GPU quota in your GCP project for the selected region.

### Step 1: Deploy the Gateway

This manifest creates the Gateway, which provisions the external load balancer.

```bash
kubectl apply -f gateway.yaml
kubectl apply -f gateway-access.yaml
```

### Step 2: Deploy the "Blue" Environment

Deploy the initial version of the VLLM inference server. This will be our live "blue" environment.

```bash
kubectl apply -f blue-vllm-deployment.yaml
kubectl apply -f blue-vllm-service.yaml
kubectl apply -f blue-health-policy.yaml
```

### Step 3: Route Traffic to the "Blue" Environment

Apply the `HTTPRoute` manifest to direct 100% of incoming traffic to the `blue-llm-service`.

```bash
kubectl apply -f blue-route.yaml
```

### Step 4: Verify and Test the "Blue" Environment

**1. Check the Pod Status**

Check the status of the "blue" deployment. GKE Autopilot will automatically provision a node with an NVIDIA L4 GPU, which may take several minutes.

```bash
# Wait for the blue deployment to become available
kubectl wait --for=condition=Available --timeout=900s deployment/blue-vllm-gemma-deployment
```

**2. Get the Gateway IP Address**

It may take a few minutes for the load balancer to be provisioned. Check the status and get the IP address with the following command:

```bash
GATEWAY_IP=$(kubectl get gateway blue-green-gateway -o jsonpath='{.status.addresses[0].value}')
while [ -z "$GATEWAY_IP" ]; do
  echo "Waiting for Gateway IP..."
  sleep 10
  GATEWAY_IP=$(kubectl get gateway blue-green-gateway -o jsonpath='{.status.addresses[0].value}')
done
echo "Gateway IP: $GATEWAY_IP"
```

**3. Test the Endpoint**

Send an inference request. The response will include a header `X-Response-Service: blue-service`, confirming the request was handled by the blue environment.

```bash
curl -v http://${GATEWAY_IP}/v1/chat/completions \
  -X POST \
  -H "Content-Type: application/json" \
  -d 
    "model": "google/gemma-3-1b-it",
    "messages": [
      {
        "role": "user",
        "content": "What is a blue-green deployment?"
      }
    ]
  }
```

### Step 5: Deploy the "Green" Environment (The Upgrade)

Now, deploy the new version of the application to the "green" environment. At this point, it receives no production traffic.

```bash
kubectl apply -f green-vllm-deployment.yaml
kubectl apply -f green-vllm-service.yaml
kubectl apply -f green-health-policy.yaml
```

Wait for the "green" deployment to become available:
```bash
kubectl wait --for=condition=Available --timeout=900s deployment/green-vllm-gemma-deployment
```

### Step 6: Switch Traffic to the "Green" Environment

Atomically switch 100% of live traffic to the "green" environment by applying the `green-route.yaml` manifest. This updates the Gateway's routing rules.

```bash
kubectl apply -f green-route.yaml
```

### Step 7: Verify the "Green" Environment

Send another test request. The response header should now be `X-Response-Service: green-service`, confirming that the new version is live.

```bash
curl -v http://${GATEWAY_IP}/v1/chat/completions \
  -X POST \
  -H "Content-Type: application/json" \
  -d 
    "model": "google/gemma-3-1b-it",
    "messages": [
      {
        "role": "user",
        "content": "What is a blue-green deployment?"
      }
    ]
  }
```

### Step 8: Rollback (Optional)

If you detect issues with the "green" deployment, you can instantly roll back by reapplying the original route.

```bash
kubectl apply -f blue-route.yaml
```

### Cleanup

To remove all the resources created in this guide, delete the Kubernetes objects.

```bash
kubectl delete -f gateway.yaml
kubectl delete -f gateway-access.yaml
kubectl delete -f blue-route.yaml
kubectl delete -f green-route.yaml
kubectl delete -f blue-vllm-service.yaml
kubectl delete -f green-vllm-service.yaml
kubectl delete -f blue-vllm-deployment.yaml
kubectl delete -f green-vllm-deployment.yaml
kubectl delete -f blue-health-policy.yaml
kubectl delete -f green-health-policy.yaml
```

To delete the GKE cluster and other GCP resources, follow the cleanup steps in [SETUP.md](SETUP.md)
