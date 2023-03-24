# Instana Server on Kubernetes

Instana offers SaaS by default, and also offers flexible non-SaaS deployment patterns, so we can deploy it within a single VM, dual-VM, or even Kubernetes.

In this repo, I've hosted some deployment experiments, focusing on how to deploy Instana on K8s, be it vanilla Kubernetes or commercial distributions like Red Hat OpenShift, for learning and even POC purposes.

> Note: 
> 1. This is NOT an official guide for how to deploy Instana on Kubernetes. Instead, this is just a sharing of my (Bright Zheng) own experiments.
> 2. These experiments are not meant for production.


## Deploying Instana on single-node K8s

Refer to [single-node-k8s/README.md](./single-node-k8s/README.md).

## Deploying Instana on OpenShift

Refer to [all-in-openshift/README.md](./all-in-openshift/README.md).

## Deploying Instana on a "hybrid" env: ROKS + VM-based Datastores

Refer to [roks-with-vm-based-datastores/README.md](./roks-with-vm-based-datastores/README.md).
