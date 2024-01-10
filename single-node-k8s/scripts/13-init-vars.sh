#!/bin/bash

######### environment variables required by k8s installation section

echo "========: Exporting & checking environment variables"

# case $ID in
#   ubuntu) 
#     # Ubuntu
#     export_var_with_default "K8S_VERSION"                       "1.28.5-00"
#     ;;
#   *) 
#     # Others
#     export_var_with_default "K8S_VERSION"                       "1.28.5"
#     ;;
# esac
export_var_with_default "K8S_VERSION"                           "1.28"
export_var_with_default "CRIO_VERSION"                          "1.28"
export_var_with_default "CALICO_MANIFEST_FILE"                  "https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml"


######### environment variables required by Instana installation section

export_var_with_default "DATASTORE_MOUNT_ROOT"                  "/storage"

export_var_with_default "DATASTORE_STORAGE_CLASS_BEEINSTANA"    "local-path"
export_var_with_default "DATASTORE_SIZE_BEEINSTANA"             "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_CASSANDRA"     "local-path"
export_var_with_default "DATASTORE_SIZE_CASSANDRA"              "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_CLICKHOUSE"    "local-path"
export_var_with_default "DATASTORE_SIZE_CLICKHOUSE_DATA"        "10Gi"
export_var_with_default "DATASTORE_SIZE_CLICKHOUSE_LOG"         "1Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_ZOOKEEPER"     "local-path"
export_var_with_default "DATASTORE_SIZE_ZOOKEEPER"              "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_ELASTICSEARCH" "local-path"
export_var_with_default "DATASTORE_SIZE_ELASTICSEARCH"          "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_KAFKA"         "local-path"
export_var_with_default "DATASTORE_SIZE_KAFKA"                  "2Gi"
export_var_with_default "DATASTORE_STORAGE_CLASS_KAFKA_ZK"      "local-path"
export_var_with_default "DATASTORE_SIZE_KAFKA_ZK"               "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_POSTGRES"      "local-path"
export_var_with_default "DATASTORE_SIZE_POSTGRES"               "3Gi"

export_var_with_default DATASTORE_STORAGE_CLASS_SYNTHETICS      "local-path"
export_var_with_default DATASTORE_SIZE_SYNTHETICS               "5Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_SPANS"         "local-path"
export_var_with_default "DATASTORE_SIZE_SPANS"                  "10Gi"

export_var_with_default "INSTANA_OPERATOR_VERSION"              "261.2.0"
export_var_with_default "INSTANA_OPERATOR_IMAGETAG"             "261-2"
# case $ID in
#   ubuntu) 
#     # Ubuntu
#     export_var_with_default "INSTANA_VERSION"                   "253-1-1"
#     ;;
#   *) 
#     # Others
#     export_var_with_default "INSTANA_VERSION"                   "253_1-1"
#     ;;
# esac


quit_when_var_not_set   "INSTANA_EXPOSED_FQDN"
export_var_with_default "INSTANA_EXPOSED_PORT"                  "443"   # here I use a special NodePort 443, by default
export_var_with_default "INSTANA_EXPOSED_PORT_ACCEPTOR"         "1444"  # here I use a special NodePort 1444, by default
quit_when_var_not_set   "INSTANA_AGENT_KEY"
quit_when_var_not_set   "INSTANA_DOWNLOAD_KEY"
quit_when_var_not_set   "INSTANA_SALES_KEY"

export_var_with_default "INSTANA_ADMIN_USER"                    "admin@instana.local"
export_var_with_default "INSTANA_ADMIN_PWD"                     "Passw0rd"
export_var_with_default "INSTANA_KEY_PASSPHRASE"                "Passw0rd"

######### Random passwords for Instana components

export CASSANDRA_PASSWORD=`openssl rand -hex 12`
export CASSANDRA_ADMIN_PASSWORD=`openssl rand -hex 12`
export CLICKHOUSE_PASSWORD=`openssl rand -hex 12`
export CLICKHOUSE_ADMIN_PASSWORD=`openssl rand -hex 12`
export ELASTICSEARCH_PASSWORD=`openssl rand -hex 12`
export ELASTICSEARCH_ADMIN_PASSWORD=`openssl rand -hex 12`
export BEEINSTANA_ADMIN_PASSWORD=`openssl rand -hex 12`
export BEEINSTANA_KAFKA_PASSWORD=`openssl rand -hex 12`


######### Check required tools

missed_tools=0
echo "========: Checking tools"
echo "Some tools will be installed automatically, which include: "
logme "$color_green" "kubelet, kubeadm, kubectl, cri-o, yq"

echo "And, there are some other tools required, which typically will be there already but let's have a check..."
# check curl
if is_required_tool_missed "curl"; then missed_tools=$((missed_tools+1)); fi
# check openssl
if is_required_tool_missed "openssl"; then missed_tools=$((missed_tools+1)); fi
# final check
if [[ $missed_tools > 0 ]]; then
  logme "$color_red"  "Abort! There are some required tools missing, please have a check."
fi

echo "========: Result"
logme "$color_yellow" "If you don't see any $color_red RED ERRORS $color_end, you're ready to proceed."
logme "$color_yellow" "you may double check the variables exported, by: env | egrep \"DATASTORE_|INSTANA_\""
