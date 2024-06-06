#!/bin/bash

### Creating namespaces
function creating-namespaces {
  logme "$color_green" "----> creating-namespaces"

  kubectl apply -f manifests/namespaces.yaml
  logme "$color_green" "DONE"
}

### Installing Cert Manager
function installing-cert-manager {
  logme "$color_green" "----> installing-cert-manager"

  # Installing Cert Manager
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml

  logme "$color_green" "DONE"
}

### Installing Datastore Kafka
function installing-datastore-kafka {
  logme "$color_green" "----> installing-datastore-kafka"

  # Ref: https://github.com/strimzi/strimzi-kafka-operator/tree/main/helm-charts/helm3/strimzi-kafka-operator
  helm repo add strimzi https://strimzi.io/charts/
  helm repo update

  helm uninstall strimzi-kafka-operator -n instana-kafka > /dev/null 2>&1 || true
  helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator -n instana-kafka \
    --version=0.38.0
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

  helm uninstall eck-operator -n instana-elasticsearch > /dev/null 2>&1 || true
  helm install eck-operator elastic/eck-operator -n instana-elasticsearch \
    --version=2.10.0
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

  helm uninstall postgres-operator -n instana-postgres > /dev/null 2>&1 || true
  helm install postgres-operator postgres/postgres-operator -n instana-postgres \
    --version=1.10.1 \
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

  helm uninstall cass-operator -n instana-cassandra > /dev/null 2>&1 || true
  helm install cass-operator k8ssandra/cass-operator -n instana-cassandra \
    --version=0.45.2
    #--set=global.clusterScoped=true \

  # Create secret
  kubectl delete secret/instana-registry -n instana-cassandra > /dev/null 2>&1 || true
  kubectl create secret docker-registry instana-registry -n instana-cassandra \
    --docker-server=artifact-public.instana.io \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}"

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

  helm uninstall zookeeper-operator -n instana-clickhouse > /dev/null 2>&1 || true
  helm install zookeeper-operator pravega/zookeeper-operator -n instana-clickhouse \
    --version=0.2.15
    #--set=watchNamespace="instana-datastore-components"
  
  envsubst < manifests/datastore-zookeeper.yaml | kubectl apply -f -

  helm repo add instana https://artifact-public.instana.io/artifactory/rel-helm-customer-virtual \
    --username _ \
    --password "${INSTANA_DOWNLOAD_KEY}"
  helm repo update

  # check available version by:
  # helm search repo instana/ibm-clickhouse-operator --versions

  # Create secret
  kubectl delete secret/instana-registry -n instana-clickhouse > /dev/null 2>&1 || true
  kubectl create secret docker-registry instana-registry -n instana-clickhouse \
    --docker-server=artifact-public.instana.io \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}"
  
  # Install Operator
  helm uninstall ibm-clickhouse-operator -n instana-clickhouse > /dev/null 2>&1 || true
  helm install ibm-clickhouse-operator instana/ibm-clickhouse-operator -n instana-clickhouse \
    --version=0.1.2

  # Create CR
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

  kubectl delete secret/instana-registry -n instana-beeinstana > /dev/null 2>&1 || true
  kubectl create secret docker-registry instana-registry -n instana-beeinstana \
    --docker-server=artifact-public.instana.io \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}"
  
  helm uninstall instana-beeinstana -n instana-beeinstana > /dev/null 2>&1 || true
  helm install instana-beeinstana instana/beeinstana-operator -n instana-beeinstana
    #--set=clusterScope=true \
    #--set=operatorWatchNamespace="instana-datastore-components" \

  echo "----> BeeInstana CR"
  envsubst < manifests/beeinstana.yaml | kubectl apply -f -

  logme "$color_green" "DONE"
}

### Installing Instana Operator
function installing-instana-operator {
  logme "$color_green" "----> installing-instana-operator"

  echo "----> Instana operator"
  helm repo add instana https://helm.instana.io/artifactory/rel-helm-customer-virtual \
    --username _ \
    --password "${INSTANA_AGENT_KEY}"
  helm repo update

  # Create the secret
  kubectl delete secret/instana-registry -n instana-operator > /dev/null 2>&1 || true
  kubectl create secret docker-registry instana-registry -n instana-operator \
    --docker-server=artifact-public.instana.io \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}"

  # Install operator
  helm uninstall instana-operator -n instana-operator > /dev/null 2>&1 || true
  helm install instana-operator instana/instana-operator -n instana-operator \
    --version=${INSTANA_OPERATOR_VERSION} \
    --set=image.tag=${INSTANA_OPERATOR_IMAGETAG} \
    --values manifests/operator-values.yaml

  logme "$color_green" "DONE"
}

function installing-instana-server-secret-image-pullsecret {
  logme "$color_green" "----> installing-instana-server-secret-image-pullsecret"

  # Create image pull secrets in both namespaces
  for n in {"instana-core","instana-units"}; do
    kubectl delete secret/instana-registry -n "${n}" > /dev/null 2>&1 || true
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
  cassandra_password="`kubectl get secret instana-cassandra -n instana-cassandra --template='{{index .data.password | base64decode}}'`" && \
  cassandra_admin_password="`kubectl get secret instana-cassandra-admin -n instana-cassandra --template='{{index .data.password | base64decode}}'`" && \
  elasticsearch_password="`kubectl get secret instana-elasticsearch -n instana-elasticsearch --template='{{index .data.password | base64decode}}'`" && \
  elasticsearch_admin_password="`kubectl get secret instana-elasticsearch-admin -n instana-elasticsearch --template='{{index .data.password | base64decode}}'`" && \
  kafka_password="`kubectl get secret instana -n instana-kafka --template='{{index .data.password | base64decode}}'`" && \
  kafka_admin_password="`kubectl get secret instanaadmin -n instana-kafka --template='{{index .data.password | base64decode}}'`" && \
  postgres_password="`kubectl get secret postgres.instana-postgres.credentials.postgresql.acid.zalan.do -n instana-postgres --template='{{index .data.password | base64decode}}'`" && \
  beeinstana_password="`kubectl get secret instana-beeinstana-admin -n instana-beeinstana --template='{{index .data.password | base64decode}}'`" && \
  cp manifests/core-config.yaml _wip/core-config.yaml && \
  yq -i "
    .adminPassword = \"${INSTANA_ADMIN_PWD}\" |
    .dhParams = \"${dhparams}\" |
    .downloadKey = \"${INSTANA_DOWNLOAD_KEY}\" |
    .salesKey = \"${INSTANA_SALES_KEY}\" |
    .serviceProviderConfig.keyPassword = \"${sp_keyPassword}\" |
    .serviceProviderConfig.pem = \"${sp_pem}\" |
    .datastoreConfigs.cassandraConfigs.[0].password = \"${cassandra_password}\" |
    .datastoreConfigs.cassandraConfigs.[0].adminPassword = \"${cassandra_admin_password}\" |
    .datastoreConfigs.clickhouseConfigs.[0].password = \"${CLICKHOUSE_PASSWORD}\" |
    .datastoreConfigs.clickhouseConfigs.[0].adminPassword = \"${CLICKHOUSE_ADMIN_PASSWORD}\" |
    .datastoreConfigs.elasticsearchConfig.password = \"${elasticsearch_password}\" |
    .datastoreConfigs.elasticsearchConfig.adminPassword = \"${elasticsearch_admin_password}\" |
    .datastoreConfigs.kafkaConfig.adminPassword = \"${kafka_admin_password}\" |
    .datastoreConfigs.kafkaConfig.consumerPassword = \"${kafka_password}\" |
    .datastoreConfigs.kafkaConfig.producerPassword = \"${kafka_password}\" |
    .datastoreConfigs.postgresConfigs.[0].password = \"${postgres_password}\" |
    .datastoreConfigs.postgresConfigs.[0].adminPassword = \"${postgres_password}\" |
    .datastoreConfigs.beeInstanaConfig.password = \"${beeinstana_password}\"
  " _wip/core-config.yaml

  # Create instana-core secret with the config file
  # Please note the key must be "config.yaml"
  kubectl delete secret/instana-core -n instana-core > /dev/null 2>&1 || true
  kubectl create secret generic instana-core -n instana-core \
    --from-file=config.yaml=_wip/core-config.yaml
  
  logme "$color_green" "DONE"
}

function installing-instana-server-secret-instana-tls {
  logme "$color_green" "----> installing-instana-server-secret-instana-tls"

  local signing_fqdn="$(get-signing-fqdn "${INSTANA_EXPOSED_FQDN}")"
  logme "$color_green" "the signed FQDN for TLS is: ${signing_fqdn}"

  openssl req -x509 -newkey rsa:2048 -keyout \
    _wip/tls.key -out _wip/tls.crt -days 365 -nodes \
    -subj "/CN=${signing_fqdn}"

  kubectl delete secret/instana-tls -n instana-core > /dev/null 2>&1 || true
  kubectl create secret tls instana-tls -n instana-core \
    --cert=_wip/tls.crt \
    --key=_wip/tls.key
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
  kubectl delete secret/tenant0-unit0 -n instana-units > /dev/null 2>&1 || true
  kubectl create secret generic tenant0-unit0 -n instana-units \
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
  echo "You should be able to access Instana UI by:"
  echo " - URL: https://${INSTANA_EXPOSED_FQDN}:${INSTANA_EXPOSED_PORT}"
  echo " - USER: ${INSTANA_ADMIN_USER}"
  echo " - PASSWORD: ${INSTANA_ADMIN_PWD}"
  logme "$color_green" "#################################################"
}
