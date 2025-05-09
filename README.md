# Summary: AI Inference on GKE

## VLLM/GPU/Gemma 3 1B/Hugging Face

[VLLM-GPU](./vllm-gpu/README.md)

- Cluster: GKE
- Accelerator: GPU (Nvidia L4)
- AI Inference Server: [vLLM](https://docs.vllm.ai/en/latest/)
- Model: Gemma 3 (1 Billion Parameters)
  - File: gemma-3-1b-it
  - Model Repo: [Hugging Face](https://huggingface.co/google/gemma-3-1b-it)

## Jetstream/TPU/Gemma 3 7B/Kaggle

[Jetstream-TPU](./jetstream-tpu/README.md)

- Cluster: GKE
- Accelerator: [TPU](https://cloud.google.com/kubernetes-engine/docs/concepts/tpus#availability)
- AI Inference Server: [Jetstream](https://github.com/AI-Hypercomputer/JetStream)
- Model: Gemma 3 (7 Billion Parameters)
  - File: gemma-3-7b-it
  - Model Repo: [Kaggle](https://www.kaggle.com/models/google/gemma)

## Single Custom Resource Versions of vLLM and Jetstream AI Inference

[AI Inference on GKE using KRO/KCC](./kcc-kro/README.md)
