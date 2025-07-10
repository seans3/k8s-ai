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

## III. Deploy Horizontal Pod Autoscaler

## IV. Test

## V. Cleanup
