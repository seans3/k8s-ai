# AI Inference on GKE

Please follow the [pre requisites](prerequisite.md) to setup the inference cluster

## VLLM/GPU/Gemma 3 1B/Hugging Face

Create this kubernetes resource to start serving Gemma 1B on Nvidia L4 GPUs

```bash
kubectl apply -f - <<EOF
apiVersion: kro.run/v1alpha1
kind: GemmaOnNvidiaL4Server
metadata:
  name: gemma-l4
  namespace: config-connector
spec:               ## KRO/BUG: Requires .spec.replicas even if all spec fields are optional
  replicas: 1
EOF
```

- Cluster: GKE
- Accelerator: GPU (Nvidia L4)
- AI Inference Server: [vLLM](https://docs.vllm.ai/en/latest/)
- Model: Gemma 3 (1 Billion Parameters)
  - File: gemma-3-1b-it
  - Model Repo: [Hugging Face](https://huggingface.co/google/gemma-3-1b-it)
