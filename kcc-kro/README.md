# AI Inference on GKE

Please follow the [pre requisites](prerequisite.md) to setup the inference cluster

## VLLM/GPU/Gemma 3 1B/Hugging Face

Create this kubernetes resource to start serving [Gemma 1B](https://huggingface.co/google/gemma-3-1b-it) on Nvidia L4 GPUs using [vLLM](https://docs.vllm.ai/en/latest/) 

```bash
kubectl apply -f - <<EOF
apiVersion: kro.run/v1alpha1
kind: GemmaOnNvidiaL4Server
metadata:
  name: gemma-l4
  namespace: config-connector
spec:               ## TODO KRO/BUG: Requires .spec.replicas even if all spec fields are optional
  replicas: 1
EOF
```

## Jetstream/TPU/Gemma 3 7B/Kaggle

Create this kubernetes resource to start serving [Gemma 7B](https://www.kaggle.com/models/google/gemma) on Nvidia L4 GPUs using [Jetstream](https://github.com/AI-Hypercomputer/JetStream)

```bash
kubectl apply -f - <<EOF
apiVersion: kro.run/v1alpha1
kind: GemmaOnTPUServer
metadata:
  name: gemma-tpu
  namespace: config-connector
spec:
  project: ${PROJECT_ID}
EOF
```

Verify resources were created:

```bash
kubectl get iamserviceaccount -n ${NAMESPACE}
kubectl get iampolicymember -n ${NAMESPACE}
kubectl get iampartialpolicy -n ${NAMESPACE}
kubectl get storagebucket -n ${NAMESPACE}
kubectl get job -n ${NAMESPACE}
kubectl get deployment -n ${NAMESPACE}
kubectl get service -n ${NAMESPACE}

```