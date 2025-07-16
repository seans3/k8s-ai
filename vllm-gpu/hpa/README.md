# Horizontal Pod Autoscaling AI Inference Server

This exercise shows how to set up the infrastructure to automatically
scale an AI inference server, using custom metrics (either server
or GPU metrics). This exercise requires Managed Prometheus service,
which is automatically enabled for GKE clusters >= v1.27. We assume
you already have the vLLM AI inference server running from this
[exercise](../README.md), in the parent directory.

## I. HPA for vLLM AI Inference Server using vLLM metrics

[vLLM AI Inference Server HPA](./vllm-hpa.md)

## II. HPA for vLLM AI Inference Server using NVidia GPU metrics

[vLLM AI Inference Server HPA with GPU metrics](./gpu-hpa.md)
