#!/bin/bash

export INIT_STATUS="DONE"   # a flag to avoid seeing the verbose init process for vars
source ./1-init-all.sh

## Let's orchestrate the process here for Instana
echo "#################################################"

creating-namespaces

installing-cert-manager
# check before proceeding: wait 5 mins for expected 3 pods
check-namespaced-pod-status-and-keep-displaying-info "cert-manager" 5 3 "kubectl get pod -n cert-manager"

installing-datastore-kafka
installing-datastore-elasticsearch
installing-datastore-postgres
installing-datastore-cassandra
installing-datastore-clickhouse

installing-beeinstana
# check before proceeding: wait 10 mins for expected 4 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-beeinstana" 10 4 "kubectl get pod -n instana-beeinstana"

installing-instana-operator
# check before proceeding: wait 8 mins for expected 2 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-operator" 8 2 "kubectl get pod -n instana-operator"

installing-instana-server-secret-image-pullsecret
installing-instana-server-secret-instana-core
installing-instana-server-secret-instana-tls
installing-instana-server-secret-tenant0-unit0

installing-instana-server-core
# check before proceeding: wait 20 mins for expected 21 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-core" 20 21 "kubectl get pod -n instana-core"

installing-instana-server-unit
# check before proceeding: wait 10 mins for expected 6 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-units" 10 6 "kubectl get pod -n instana-units"

exposing-instana-server-services


## Print out the access info
echo "#################################################"
how-to-access-instana
