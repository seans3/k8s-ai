# AI Inference on GKE using KCC and KRO

Please follow the [prerequisites](prerequisite.md) to setup the inference cluster

## VLLM/GPU/Gemma 3 1B/Hugging Face

Create this kubernetes resource to start serving [Gemma 1B](https://huggingface.co/google/gemma-3-1b-it) on Nvidia L4 GPUs using [vLLM](https://docs.vllm.ai/en/latest/) 

```bash
kubectl apply -f - <<EOF
apiVersion: kro.run/v1alpha1
kind: GemmaOnNvidiaL4Server
metadata:
  name: gemma-l4
  namespace: ${NAMESPACE}
spec:               ## TODO KRO/BUG: Requires .spec.replicas even if all spec fields are optional
  replicas: 1
EOF
```

Verify resources were created:

```bash
kubectl get deployment -n ${NAMESPACE}
kubectl get service -n ${NAMESPACE}

```

### Query the vLLM/NVidia L4 AI Inference Server

#### Port-Forward from local port to inference container port

Ensure the name of the service is `gemma-l4` and the container port is `8081`. Then start the port-forward from the local port to the container port.

```bash
kubectl port-forward svc/gemma-l4 -n ${NAMESPACE} 8081:8081
```

#### Run curl command to query inference server

Run a curl command pointed at the local port `8081`

```bash
curl http://127.0.0.1:8081/v1/chat/completions \
-X POST \
-H "Content-Type: application/json" \
-d '{
    "model": "google/gemma-3-1b-it",
    "messages": [
        {
          "role": "user",
          "content": "Why is the sky blue?"
        }
    ]
}'
```


## Jetstream/TPU/Gemma 3 7B/Kaggle

Create this kubernetes resource to start serving [Gemma 7B](https://www.kaggle.com/models/google/gemma) on TPU's using [Jetstream](https://github.com/AI-Hypercomputer/JetStream)

```bash
kubectl apply -f - <<EOF
apiVersion: kro.run/v1alpha1
kind: GemmaOnTPUServer
metadata:
  name: gemma-tpu
  namespace: ${NAMESPACE}
spec:
  project: ${PROJECT_ID}
EOF
```

This custom resource should perform the following steps:

1. Create necessary IAM resources.
2. Create a GCS bucket used to communicate the model between the transformation job and the deployment servers.
3. Start the job necessary to transform the Gemma model on Kaggle into the format necessary for the Jetstream AI inference server.
4. Start the Jetstream AI inference server deployment.
5. Start the service in front of the AI inference servers.

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


### Query the TPU AI Inference Server

#### Port-Forward from local port to inference container port

Ensure the name of the service is `gemma-tpu` and the container port is `8000`. Then start the port-forward from the local port to the container port.

```bash
kubectl port-forward svc/gemma-tpu -n ${NAMESPACE} 8000:8000
```

#### Run curl command to query inference server

Run a curl command pointed at the local port `8000`

```bash
curl --request POST \
--header "Content-type: application/json" \
-s \
localhost:8000/generate \
--data \
'{
    "prompt": "What are the top 5 programming languages",
    "max_tokens": 200
}'
```

The response should look like:

```bash
{
    "response": "\nfor data science in 2023?\n\n**1. Python:**\n- Widely used for data science due to its simplicity, readability, and extensive libraries for data wrangling, analysis, visualization, and machine learning.\n- Popular libraries include pandas, scikit-learn, and matplotlib.\n\n**2. R:**\n- Statistical programming language widely used for data analysis, visualization, and modeling.\n- Popular libraries include ggplot2, dplyr, and caret.\n\n**3. Java:**\n- Enterprise-grade language with strong performance and scalability.\n- Popular libraries include Spark, TensorFlow, and Weka.\n\n**4. C++:**\n- High-performance language often used for data analytics and machine learning models.\n- Popular libraries include TensorFlow, PyTorch, and OpenCV.\n\n**5. SQL:**\n- Relational database language essential for data wrangling and querying large datasets.\n- Popular tools"
}
```
