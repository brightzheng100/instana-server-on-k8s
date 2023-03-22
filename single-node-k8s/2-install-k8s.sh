#!/bin/bash

export INIT_STATUS="DONE"   # a flag to avoid seeing the verbose init process for vars
source ./1-init-all.sh

## Let's orchestrate the process here for K8s
echo "#################################################"

installing-k8s-tools
installing-k8s-cri

bootstrapping-k8s
progress-bar 1

getting-ready-k8s
installing-k8s-cni
