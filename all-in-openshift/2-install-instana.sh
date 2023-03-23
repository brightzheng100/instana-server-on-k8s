#!/bin/bash

export INIT_STATUS="DONE"   # a flag to avoid seeing the verbose init process for vars
source ./1-init-all.sh

## Let's orchestrate the process here for Instana
echo "#################################################"

installing-tools
creating-namespaces
installing-local-path-provisioner

installing-cert-manager
# check before proceeding: wait 5 mins for expected 3 pods
check-namespaced-pod-status-and-keep-displaying-info "cert-manager" 5 3 "kubectl get pod -n cert-manager"

installing-instana-operator

installing-instana-datastores
# check before proceeding: wait 10 mins for expected 8 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-datastores" 10 8 "kubectl get pod -n instana-datastores"

installing-instana-server-components-secret-image-pullsecret
installing-instana-server-components-secret-instana-core
installing-instana-server-components-secret-instana-tls
installing-instana-server-components-secret-tenant0-unit0

installing-instana-server-components-core
# check before proceeding: wait 10 mins for expected 20 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-core" 10 20 "kubectl get pod -n instana-core"

installing-instana-server-components-unit
# check before proceeding: wait 10 mins for expected 6 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-units" 10 6 "kubectl get pod -n instana-units"

exposing-instana-server-servies


## Print out the access info
echo "#################################################"
how-to-access-instana
