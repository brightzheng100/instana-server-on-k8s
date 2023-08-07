#!/bin/bash

# Important Notes:
# This is the "overlay" of <root>/single-node-k8s/scripts/12-init-instana.sh
# Only functions changed will be here for replacement

function installing-scc {
  echo "----> installing-scc"
  kubectl apply -f manifests/scc.yaml

  logme "$color_green" "DONE"
}

### Installing Datastore Postgres
function installing-datastore-postgres {
  logme "$color_green" "----> installing-datastore-postgres"

  # Ref: https://github.com/zalando/postgres-operator/blob/master/charts/postgres-operator/values.yaml
  helm repo add postgres https://opensource.zalando.com/postgres-operator/charts/postgres-operator
  helm repo update
  helm install postgres-operator postgres/postgres-operator -n instana-postgres \
    --version=1.9.0 \
    --set=configGeneral.kubernetes_use_configmaps=true \
    --set securityContext.runAsUser=101
    #--set=configKubernetes.watched_namespace="instana-datastore-components" \

  envsubst < manifests/datastore-postgres.yaml | kubectl apply -f -

  logme "$color_green" "Postgres - DONE"
}

### Installing Datastore Cassandra
function installing-datastore-cassandra {
  logme "$color_green" "----> installing-datastore-cassandra"

  # Ref: https://docs.k8ssandra.io/reference/helm-chart/k8ssandra-operator/
  helm repo add k8ssandra https://helm.k8ssandra.io/stable
  helm repo update
  helm install cass-operator k8ssandra/cass-operator -n instana-cassandra \
    --version=0.42.0 \
    --set securityContext.runAsGroup=999 \
    --set securityContext.runAsUser=999
    #--set=global.clusterScoped=true \

  progress-bar 2

  envsubst < manifests/datastore-cassandra.yaml | kubectl apply -f -

  logme "$color_green" "Cassandra - DONE"
}

### Installing Instana's BeeInstana
function installing-beeinstana {
  logme "$color_green" "----> installing-beeinstana"

  echo "----> BeeInstana operator"
  helm repo add instana https://helm.instana.io/artifactory/rel-helm-customer-virtual \
    --username _ \
    --password "${INSTANA_AGENT_KEY}"
  helm repo update

  kubectl create secret docker-registry instana-registry \
    --namespace=instana-beeinstana \
    --docker-server=artifact-public.instana.io \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}"
  
  helm install instana-beeinstana instana/beeinstana-operator \
    --namespace=instana-beeinstana \
    --set operator.securityContext.seccompProfile.type=RuntimeDefault
    #--set=clusterScope=true \
    #--set=operatorWatchNamespace="instana-datastore-components" \

  echo "----> BeeInstana CR"
  fsGroup="`oc get namespace instana-beeinstana -o jsonpath='{.metadata.annotations.openshift\.io\/sa\.scc\.uid-range}' | cut -d/ -f 1`" \
    envsubst < manifests/beeinstana.yaml | kubectl apply -f -

  logme "$color_green" "DONE"
}

function exposing-instana-server-services {
  echo "----> exposing-instana-server-servies"

    # Create routes for gateway
  oc create route passthrough instana-gateway \
    --hostname="`kubectl get core/instana-core -n instana-core -o jsonpath='{.spec.baseDomain}'`" \
    --service=gateway \
    --port=https \
    -n instana-core
  oc create route passthrough instana-gateway-unit0-tenant0 \
    --hostname="unit0-tenant0.`kubectl get core/instana-core -n instana-core -o jsonpath='{.spec.baseDomain}'`" \
    --service=gateway \
    --port=https \
    -n instana-core

  # Create routes for acceptor
  oc create route passthrough instana-acceptor \
    --hostname="`kubectl get core/instana-core -n instana-core -o jsonpath='{.spec.agentAcceptorConfig.host}'`" \
    --service=acceptor \
    --port=http-service \
    -n instana-core
  
  logme "$color_green" "DONE"
}

function how-to-access-instana {
  local url="$( oc get route -n instana-core instana-gateway -o jsonpath='{.spec.host}' )"

  echo "You should be able to acdess Instana UI by:"
  echo " - URL: https://${url}"
  echo " - USER: ${INSTANA_ADMIN_USER}"
  echo " - PASSWORD: ${INSTANA_ADMIN_PWD}"
}
