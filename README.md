# Instana Server on Kubernetes

Instana offers SaaS by default, and also offers flexible non-SaaS deployment patterns, so we can deploy it within a single VM, dual-VM, or even Kubernetes.

In this repo, I've hosted some deployment experiments, focusing on how to deploy Instana on K8s, be it vanilla Kubernetes or commercial distributions like Red Hat OpenShift, for learning and maybe POC purposes.

> Note: 
> 1. This is NOT an official guide for how to deploy Instana on Kubernetes. Instead, this is just a sharing of my (Bright Zheng) own experiments. Instana is very agile with bi-weekly release cadence for SaaS and monthly for on-prem, so try this "unofficial" stuff with luck and please always refer to the official docs.
> 2. These experiments are not meant for production, at all.


## How this repo is structured

There are some concepts like "modularization" and "reusability" and I like them, which also apply into how this repo is structured.

Very simple, I built the `single-node-k8s` first and try to reuse what I've built with necesary "overlay" code/scripts, so:

```
all-in-k8s (REVIEW IN PROGRESS)
all-in-openshift (REVIEW IN PROGRESS)

      |
      |
   Depend on
      |
      V

single-node-k8s
```

Actually, there are only very few changes needed to make on top of the `single-node-k8s`.


## Deploying Instana on single-node K8s

Refer to [single-node-k8s/README.md](./single-node-k8s/README.md).


## Deploying Instana on K8s

TODO


## Deploying Instana on OpenShift

Refer to [all-in-openshift/README.md](./all-in-openshift/README.md).


## Deploying Instana on a "hybrid" env: ROKS + VM-based Datastores

Well, copied from my archived [`brightzheng100/instana-server-on-roks`](https://github.com/brightzheng100/instana-server-on-roks) and not yet to further review.

Refer to [roks-with-vm-based-datastores/README.md](./roks-with-vm-based-datastores/README.md).
