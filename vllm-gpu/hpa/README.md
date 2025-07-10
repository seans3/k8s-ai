# Horizontal Pod Autoscaling AI Inference Server

This exercise assumes you already have the vLLM AI inference server
running from this [exercise](../README.md).

## I. Collect Metrics into Managed Prometheus

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
