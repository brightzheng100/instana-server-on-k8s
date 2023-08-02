#!/bin/bash

### Creating namespaces
function creating-namespaces {
  logme "$color_green" "----> creating-namespaces"

  kubectl apply -f manifests/namespaces.yaml
  logme "$color_green" "DONE"
}

### Installing local-path-provisioner
function installing-local-path-provisioner {
  logme "$color_green" "----> installing-local-path-provisioner"

  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.23/deploy/local-path-storage.yaml

  cat manifests/local-path-config.yaml |  envsubst '$DATASTORE_MOUNT_ROOT' | kubectl apply -f -

  logme "$color_green" "DONE"
}

### Installing Cert Manager
function installing-cert-manager {
  logme "$color_green" "----> installing-cert-manager"

  # Installing Cert Manager
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml

  logme "$color_green" "DONE"
}

### Installing Datastore Kafka
function installing-datastore-kafka {
  logme "$color_green" "----> installing-datastore-kafka"

  # Ref: https://github.com/strimzi/strimzi-kafka-operator/tree/main/helm-charts/helm3/strimzi-kafka-operator
  helm repo add strimzi https://strimzi.io/charts/
  helm repo update
  helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator -n instana-kafka \
    --version=0.35.1
    #--set=watchNamespaces="{instana-datastore-components}" \
  
  envsubst < manifests/datastore-kafka.yaml | kubectl apply -f -

  logme "$color_green" "Kafka - DONE"
}

### Installing Datastore ElasticSearch
function installing-datastore-elasticsearch {
  logme "$color_green" "----> installing-datastore-elasticsearch"

  # Ref: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-stack-helm-chart.html
  helm repo add elastic https://helm.elastic.co
  helm repo update
  helm install eck-operator elastic/eck-operator -n instana-elasticsearch \
    --version=2.5.0
    #--set=managedNamespaces="{instana-datastore-components}" \
  
  envsubst < manifests/datastore-elasticsearch.yaml | kubectl apply -f -

  logme "$color_green" "Elasticsearch - DONE"
}

### Installing Datastore Postgres
function installing-datastore-postgres {
  logme "$color_green" "----> installing-datastore-postgres"

  # Ref: https://github.com/zalando/postgres-operator/blob/master/charts/postgres-operator/values.yaml
  helm repo add postgres https://opensource.zalando.com/postgres-operator/charts/postgres-operator
  helm repo update
  helm install postgres-operator postgres/postgres-operator -n instana-postgres \
    --version=1.9.0 \
    --set=configGeneral.kubernetes_use_configmaps=true
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
    --version=0.40.0
    #--set=global.clusterScoped=true \

  progress-bar 2

  envsubst < manifests/datastore-cassandra.yaml | kubectl apply -f -

  logme "$color_green" "Cassandra - DONE"
}

### Installing Datastore Clickhouse
function installing-datastore-clickhouse {
  logme "$color_green" "----> installing-datastore-clickhouse"

  # Note: currently the dedicated ZooKeeper is for ClickHouse only 
  #       and may be removed once ClickHouse is transitioned to ClickHouse Keeper
  # Ref: https://github.com/pravega/zookeeper-operator/tree/master/charts/zookeeper-operator
  helm repo add pravega https://charts.pravega.io
  helm repo update
  helm install zookeeper-operator pravega/zookeeper-operator -n instana-clickhouse \
    --version=0.2.15
    #--set=watchNamespace="instana-datastore-components"
  
  envsubst < manifests/datastore-zookeeper.yaml | kubectl apply -f -

  # Ref: 
  cat manifests/datastore-clickhouse-operator.yaml | \
    sed 's|kube-system|instana-clickhouse|g' | \
    kubectl apply -f -
    #sed 's|namespaces: \[\]|namespaces: \[instana-datastore-components\]|g' | \

  kubectl create secret docker-registry instana-registry \
    --namespace=instana-clickhouse \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}" \
    --docker-server=artifact-public.instana.io

  envsubst < manifests/datastore-clickhouse.yaml | kubectl apply -f -

  logme "$color_green" "ClickHouse - DONE"
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
    --namespace=instana-beeinstana
    #--set=clusterScope=true \
    #--set=operatorWatchNamespace="instana-datastore-components" \

  echo "----> BeeInstana CR"
  envsubst < manifests/beeinstana.yaml | kubectl apply -f -

  logme "$color_green" "DONE"
}

### Installing Instana Operator
function installing-instana-operator {
  logme "$color_green" "----> installing-instana-operator"

  # Create the secret
  kubectl create secret docker-registry instana-registry \
    --namespace=instana-operator \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}" \
    --docker-server=artifact-public.instana.io

  # Apply the Instana Operator
  kubectl instana operator apply \
    --namespace=instana-operator \
    --values manifests/operator-values.yaml

  logme "$color_green" "DONE"
}

function installing-instana-server-secret-image-pullsecret {
  logme "$color_green" "----> installing-instana-server-secret-image-pullsecret"

  # Create image pull secrets in both namespaces
  for n in {"instana-core","instana-units"}; do
    kubectl create secret docker-registry instana-registry \
      --namespace="${n}" \
      --docker-username=_ \
      --docker-password="${INSTANA_AGENT_KEY}" \
      --docker-server=artifact-public.instana.io
  done

  logme "$color_green" "DONE"
}

function installing-instana-server-secret-instana-core {
  logme "$color_green" "----> installing-instana-server-secret-instana-core"

  kubectl delete secret/instana-core --namespace instana-core || true

  # Prepare Secret: `instana-core`
  # dhParams
  openssl dhparam -out _wip/dhparams.pem 2048
  # An key for signing/validating messages exchanged with the IDP must be configured. 
  # Unencrypted keys won't be accepted
  openssl genrsa -aes128 -out _wip/key.pem -passout pass:"${INSTANA_KEY_PASSPHRASE}" 2048
  openssl req -new -x509 -key _wip/key.pem -out _wip/cert.pem -passin pass:"${INSTANA_KEY_PASSPHRASE}" -days 365 \
    -subj "/C=SG/ST=SG/L=SG/O=IBM/OU=AIOps/CN=ibm.com"
  cat _wip/key.pem _wip/cert.pem > _wip/sp.pem

  # Prepare the core config file
  dhparams="`cat _wip/dhparams.pem`" && \
  sp_keyPassword="${INSTANA_KEY_PASSPHRASE}" && \
  sp_pem="`cat _wip/sp.pem`" && \
  cassandra_password="`kubectl get secret instana-superuser -n instana-cassandra --template='{{index .data.password | base64decode}}'`" && \
  clickhouse_password="clickhouse-pass" && \
  elasticsearch_password="`kubectl get secret instana-elasticsearch-es-elastic-user -n instana-elasticsearch --template='{{index .data.elastic | base64decode}}'`" && \
  kafka_password="`kubectl get secret kafka-user -n instana-kafka --template='{{index .data.password | base64decode}}'`" && \
  postgres_password="`kubectl get secret postgres.instana-postgres.credentials.postgresql.acid.zalan.do -n instana-postgres --template='{{index .data.password | base64decode}}'`" && \
  beeinstana_password="instana" && \
  cp manifests/core-config.yaml _wip/core-config.yaml && \
  yq -i "
    .adminPassword = \"${INSTANA_ADMIN_PWD}\" |
    .dhParams = \"${dhparams}\" |
    .downloadKey = \"${INSTANA_DOWNLOAD_KEY}\" |
    .salesKey = \"${INSTANA_SALES_KEY}\" |
    .serviceProviderConfig.keyPassword = \"${sp_keyPassword}\" |
    .serviceProviderConfig.pem = \"${sp_pem}\" |
    .datastoreConfigs.cassandraConfigs.[0].password = \"${cassandra_password}\" |
    .datastoreConfigs.cassandraConfigs.[0].adminPassword = \"${cassandra_password}\" |
    .datastoreConfigs.clickhouseConfigs.[0].password = \"${clickhouse_password}\" |
    .datastoreConfigs.clickhouseConfigs.[0].adminPassword = \"${clickhouse_password}\" |
    .datastoreConfigs.elasticsearchConfig.password = \"${elasticsearch_password}\" |
    .datastoreConfigs.elasticsearchConfig.adminPassword = \"${elasticsearch_password}\" |
    .datastoreConfigs.kafkaConfig.adminPassword = \"${kafka_password}\" |
    .datastoreConfigs.kafkaConfig.consumerPassword = \"${kafka_password}\" |
    .datastoreConfigs.kafkaConfig.producerPassword = \"${kafka_password}\" |
    .datastoreConfigs.postgresConfigs.[0].password = \"${postgres_password}\" |
    .datastoreConfigs.postgresConfigs.[0].adminPassword = \"${postgres_password}\" |
    .datastoreConfigs.beeInstanaConfig.password = \"${beeinstana_password}\" |
    .datastoreConfigs.beeInstanaConfig.adminPassword = \"${beeinstana_password}\"
  " _wip/core-config.yaml

  # Create instana-core secret with the config file
  # Please note the key must be "config.yaml"
  kubectl create secret generic instana-core \
    --namespace instana-core \
    --from-file=config.yaml=_wip/core-config.yaml
  
  logme "$color_green" "DONE"
}

function installing-instana-server-secret-instana-tls {
  logme "$color_green" "----> installing-instana-server-secret-instana-tls"

  local signing_fqdn="$(get-signing-fqdn "${INSTANA_EXPOSED_FQDN}")"
  logme "$color_green" "the signed FQDN for TLS is: ${signing_fqdn}"

  openssl req -x509 -newkey rsa:2048 -keyout \
    _wip/tls.key -out _wip/tls.crt -days 365 -nodes \
    -subj "/CN=*.${signing_fqdn}"

  kubectl create secret tls instana-tls --namespace instana-core \
    --cert=_wip/tls.crt --key=_wip/tls.key
  kubectl label secret instana-tls app.kubernetes.io/name=instana -n instana-core
  
  logme "$color_green" "DONE"
}

function installing-instana-server-secret-tenant0-unit0 {
  logme "$color_green" "----> installing-instana-server-secret-tenant0-unit0"

  # Generate and download the license file based on the sales key
  kubectl instana license download \
    --sales-key "${INSTANA_SALES_KEY}" \
    --filename _wip/license.json

  # Prepare unit config file
  license="`cat _wip/license.json`" \
    envsubst < manifests/unit-config.yaml > _wip/unit-config.yaml

  # Create tenant0-unit0 secret with the config file
  # Please note the key must be "config.yaml"
  kubectl create secret generic tenant0-unit0 \
    --namespace instana-units \
    --from-file=config.yaml=_wip/unit-config.yaml
  
  logme "$color_green" "DONE"
}

function installing-instana-server-core {
  logme "$color_green" "----> installing-instana-server-core"

  # Create the `instana-core` CR object
  envsubst < manifests/core.yaml | kubectl apply -f -
  
  logme "$color_green" "DONE"
}

function installing-instana-server-unit {
  logme "$color_green" "----> installing-instana-server-unit"

  # Create unit object
  kubectl apply -f manifests/tenant0-unit0.yaml
  
  logme "$color_green" "DONE"
}

function exposing-instana-server-services {
  logme "$color_green" "----> exposing-instana-server-servies"

  # Expose services by NodePort
  envsubst < manifests/services-with-nodeport.yaml | kubectl apply -f -
  
  logme "$color_green" "DONE"
}

function how-to-access-instana {
  logme "$color_green" "#################################################"
  echo "You should be able to acdess Instana UI by:"
  echo " - URL: https://${INSTANA_EXPOSED_FQDN}:${INSTANA_EXPOSED_PORT}"
  echo " - USER: ${INSTANA_ADMIN_USER}"
  echo " - PASSWORD: ${INSTANA_ADMIN_PWD}"
  logme "$color_green" "#################################################"
}
