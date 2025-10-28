# Tips and Tricks for GKE Cluster Setup

This guide provides tips for setting up your Google Kubernetes Engine (GKE) cluster to run the recipes in this repository. It focuses on creating GPU node pools using **Spot VMs**, which can significantly reduce costs and improve the availability of high-demand GPUs for non-production testing and experimentation.

## What are Spot VMs?

Spot VMs are spare Google Cloud compute capacity that you can use at a much lower price than standard VMs. The trade-off is that Google Cloud may reclaim these resources at any time (preemption) if they are needed for standard workloads.

**Why use Spot VMs for these recipes?**
-   **Cost Savings:** Spot VMs are up to 91% cheaper than on-demand instances, making it much more affordable to experiment with powerful GPUs like A100s and H100s.
-   **Increased Availability:** Sometimes, high-demand GPUs may not be available for on-demand use in a specific region. You often have a better chance of acquiring them by requesting them as Spot instances across multiple zones.

> **Warning:** Spot VMs are **not recommended for production workloads** due to their preemptible nature. A running inference job could be interrupted. However, they are perfect for the testing and development purposes of these recipes.

## Understanding Regional Clusters vs. Zonal Node Pools

When you create a GKE cluster with a `--region` flag (like `us-central1`), you are creating a **Regional Cluster**. This means the Kubernetes control plane is replicated across multiple zones within that region for high availability.

However, the worker nodes themselves—the actual VMs that run your pods—live in specific physical locations called **zones** (e.g., `us-central1-a`). A **Node Pool** is a group of nodes with the same configuration. When you create a node pool, you must tell GKE which zone(s) it can create the nodes in.

This is especially important for GPUs because they are physical hardware installed in specific zones. By using the `--node-locations` flag and providing a list of all the zones where a particular GPU is available, you significantly increase the chances that GKE's autoscaler can successfully acquire a node for your workload, particularly when using Spot VMs.

The `us-central1` region is often recommended as it currently has the best availability for GPUs, offering the most zones with a wide variety of accelerator types. This maximizes your chances of acquiring capacity.

## How to Find GPU Availability

The `--node-locations` flag is critical for successfully acquiring GPUs. The zones provided in the examples below are for the `us-central1` region and may change over time.

You can find the up-to-date list of zones for any GPU type and region by running the following `gcloud` command.

**Example:** To find all zones in the `us-east1` region that have `nvidia-l4` GPUs, you would run:
```bash
gcloud compute accelerator-types list \
  --filter="name='nvidia-l4' AND zone:us-east1" \
  --format="value(zone)"
```
The output will be a list of zones (e.g., `us-east1-b,us-east1-c`) that you can use for the `--node-locations` flag.

## GKE Standard vs. Autopilot

GKE offers two modes of operation: Standard and Autopilot.

-   **GKE Autopilot:** This is a fully managed mode where GKE automatically provisions and manages the underlying nodes for you based on your workload specifications. You don't create or manage node pools directly. While simpler, it offers less control over the specific node configuration. Some recipes in this repository are designed for Autopilot, but for fine-tuned control over GPU node pools, Standard is required.

-   **GKE Standard:** In this mode, you have full control over creating and configuring your own node pools. This allows you to define the exact machine types, GPU configurations, autoscaling parameters, and taints needed for your workloads.

The instructions in this guide are for a **GKE Standard** cluster because they require you to manually create and customize GPU node pools with specific features like Spot VMs and taints.

## 1. Create a Standard GKE Cluster

If you don't already have one, create a standard GKE cluster. The following command creates a basic cluster without any default GPU node pools.

```bash
export CLUSTER_NAME="your-cluster-name"
export REGION="us-central1" # Or any other region

gcloud container clusters create ${CLUSTER_NAME} \
    --region=${REGION} \
    --machine-type=e2-standard-2 \
    --num-nodes=1 \
    --release-channel=stable
```

## 2. Create GPU Node Pools with Spot VMs

Here are the commands to create the various GPU node pools used in the recipes. Each command creates a node pool that:
-   Uses the `--spot` flag to provision Spot VMs.
-   Specifies `--node-locations` with all the zones in the region where the GPU is available to increase the chances of acquiring the Spot capacity.
-   Enables autoscaling and can scale down to **zero nodes** to save costs when not in use.
-   Applies a `taint` to the nodes. This ensures that only pods that explicitly "tolerate" the GPU (like our vLLM deployments) will be scheduled on these expensive nodes.

### NVIDIA L4 GPU Node Pool (for `g2` machines)

```bash
gcloud container node-pools create gpu-l4-spot-pool \
  --cluster=${CLUSTER_NAME} \
  --region=${REGION} \
  --machine-type=g2-standard-4 \
  --accelerator=type=nvidia-l4,count=1 \
  --spot \
  --node-locations=us-central1-a,us-central1-b,us-central1-c \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=5 \
  --node-taints=nvidia.com/gpu=present:NoSchedule
```

### NVIDIA T4 GPU Node Pool (for `n1` machines)

```bash
gcloud container node-pools create gpu-t4-spot-pool \
  --cluster=${CLUSTER_NAME} \
  --region=${REGION} \
  --machine-type=n1-standard-4 \
  --accelerator=type=nvidia-tesla-t4,count=1 \
  --spot \
  --node-locations=us-central1-a,us-central1-b,us-central1-c,us-central1-f \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=5 \
  --node-taints=nvidia.com/gpu=present:NoSchedule
```

### NVIDIA A100 40GB GPU Node Pool (for `a2-highgpu` machines)

This pool is for multi-GPU workloads, attaching 4 GPUs per node.

```bash
gcloud container node-pools create a100-40gb-4-spot-pool \
  --cluster=${CLUSTER_NAME} \
  --region=${REGION} \
  --machine-type=a2-highgpu-4g \
  --accelerator=type=nvidia-tesla-a100,count=4 \
  --spot \
  --node-locations=us-central1-a,us-central1-b,us-central1-c \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=3 \
  --node-taints=nvidia.com/gpu=present:NoSchedule
```

### NVIDIA A100 80GB GPU Node Pool (for `a2-ultragpu` machines)

```bash
gcloud container node-pools create a100-80gb-spot-pool \
  --cluster=${CLUSTER_NAME} \
  --region=${REGION} \
  --machine-type=a2-ultragpu-1g \
  --accelerator=type=nvidia-a100-80gb,count=1 \
  --spot \
  --node-locations=us-central1-a,us-central1-c \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=3 \
  --node-taints=nvidia.com/gpu=present:NoSchedule
```

### NVIDIA H100 80GB GPU Node Pool (for `a3-highgpu` machines)

```bash
gcloud container node-pools create h100-80gb-spot-pool \
  --cluster=${CLUSTER_NAME} \
  --region=${REGION} \
  --machine-type=a3-highgpu-1g \
  --accelerator=type=nvidia-h100-80gb,count=1 \
  --spot \
  --node-locations=us-central1-a,us-central1-b,us-central1-c \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=3 \
  --node-taints=nvidia.com/gpu=present:NoSchedule
```

After creating these node pools, your cluster will be ready to run the various recipes. The GKE autoscaler will automatically provision a GPU node from the correct pool when you deploy a workload that requests that specific GPU type. When you delete the workload, the node pool will automatically scale back down to zero.

## 3. GPU VRAM Specifications

Before calculating the VRAM required for a model, it's important to know the VRAM available on each type of GPU accelerator.

| Accelerator Type | VRAM |
| :--- | :--- |
| NVIDIA L4 | 24 GB |
| NVIDIA T4 | 16 GB |
| NVIDIA A100 40GB | 40 GB |
| NVIDIA A100 80GB | 80 GB |
| NVIDIA H100 80GB | 80 GB |

## 4. Understanding VRAM Requirements for LLMs

Choosing the right GPU is critical, and the most important factor is its Video RAM (VRAM). The total VRAM required to run an LLM is more than just the size of the model\'s weights. It\'s a combination of the model weights, the KV cache for in-flight requests, and framework overhead.

### The VRAM Calculation Formula

A good rule of thumb for estimating the required VRAM is:

**Total VRAM = (Model Weights Size) + (KV Cache Size) + (Framework Overhead)**

Let\'s break down each component.

#### a. Model Weights Size

This is the memory needed to load the model\'s parameters onto the GPU.

-   **Formula**: `(Number of Parameters) * (Bytes per Parameter)`
-   **Bytes per Parameter**: This depends on the model\'s precision.
    -   **FP32 (32-bit float):** 4 bytes
    -   **FP16 (16-bit float):** 2 bytes
    -   **BF16 (bfloat16):** 2 bytes
    -   **INT8 (8-bit integer):** 1 byte
    -   **INT4 (4-bit integer):** 0.5 bytes

Most modern inference is done at FP16 or BF16 precision.

#### b. KV Cache Size

This is often the largest and most dynamic part of the memory usage. The Key-Value (KV) cache stores the attention state for tokens that have already been processed. This is what makes generating subsequent tokens fast, as the model doesn\'t have to re-calculate the entire sequence for each new token.

-   **Formula**: `(Batch Size) * (Sequence Length) * (Number of Layers) * (Hidden Size) * 2 * (Bytes per Parameter)`
    -   **Batch Size**: The number of concurrent requests being processed.
    -   **Sequence Length**: The maximum number of tokens (input + output) in a sequence.
    -   **Number of Layers / Hidden Size**: These are properties of the model\'s architecture.
    -   **The `* 2`** is because the cache stores both a "Key" and a "Value" for each token.

The KV cache size grows linearly with the number of concurrent requests and the sequence length. This is why serving many users or handling long documents requires a lot of VRAM.

#### c. Framework Overhead

This is the memory used by the CUDA kernels, the inference server (like vLLM), and other miscellaneous processes. It\'s typically a fixed amount, often between **2-4 GB**.

### Example: Calculating VRAM for `gemma-3-27b-it`

Let\'s apply this to the `gemma-3-27b-it` model, which is used in the [Serving Large Models with Tensor Parallelism](./vllm-gpu/large-model/README.md) recipe.

-   **Parameters**: 27 billion (27B)
-   **Precision**: `bfloat16` (2 bytes per parameter)

#### 1. Model Weights Size

`27,000,000,000 parameters * 2 bytes/parameter = 54,000,000,000 bytes = 54 GB`

Just loading the model requires **54 GB** of VRAM. This immediately tells us that a GPU with less VRAM (like an L4 with 24 GB or an A100 with 40 GB) cannot serve this model without parallelism.

#### 2. KV Cache Size (Estimated)

The exact size depends on the model\'s architecture and the workload. However, for a large model like this with a long context length (e.g., 8192 tokens), the KV cache under a moderate load can easily consume **20-30 GB** of VRAM.

### How Tensor Parallelism Solves the VRAM Problem

When a model is too large to fit into a single GPU's VRAM, you can use **Tensor Parallelism** to split the model's weights across multiple GPUs. Inference servers like vLLM control this behavior with the `--tensor-parallel-size` flag.

For example, setting `--tensor-parallel-size=4` tells vLLM to shard the model across four GPUs. This not only divides the model weights but also the KV cache and the workload for each request.

Let's revisit our `gemma-3-27b-it` example, now distributed across four A100 80GB GPUs:

-   **Model Weights per GPU**: `54 GB / 4 = 13.5 GB`
-   **KV Cache per GPU**: The KV cache is *also* sharded. So, `~25 GB / 4 = ~6.25 GB`
-   **Framework Overhead per GPU**: `~3 GB`

**Total VRAM per GPU**: `13.5 GB + 6.25 GB + 3 GB = ~22.75 GB`

This fits comfortably within the 80 GB of VRAM on each A100 GPU and leaves a massive amount of headroom for a much larger batch size, leading to higher throughput. It also shows why this setup would still not fit on four L4 GPUs (24 GB each), as the VRAM would be almost completely full before even handling a large batch of requests.
