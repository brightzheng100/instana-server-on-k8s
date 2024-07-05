#!/bin/bash
echo "========: Exporting & checking environment variables"

quit_when_var_not_set   "INSTANA_EXPOSED_FQDN"
quit_when_var_not_set   "INSTANA_AGENT_KEY"
quit_when_var_not_set   "INSTANA_DOWNLOAD_KEY"
quit_when_var_not_set   "INSTANA_SALES_KEY"

export_var_with_default "INSTANA_EXPOSED_PORT"                  "443"
export_var_with_default "INSTANA_EXPOSED_PORT_ACCEPTOR"         "443"

export_var_with_default "INSTANA_ADMIN_USER"                    "admin@instana.local"
export_var_with_default "INSTANA_ADMIN_PWD"                     "Passw0rd"
export_var_with_default "INSTANA_KEY_PASSPHRASE"                "Passw0rd"

export_var_with_default "DATASTORE_STORAGE_CLASS_BEEINSTANA"    "default"
export_var_with_default "DATASTORE_SIZE_BEEINSTANA"             "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_CASSANDRA"     "default"
export_var_with_default "DATASTORE_SIZE_CASSANDRA"              "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_CLICKHOUSE"    "default"
export_var_with_default "DATASTORE_SIZE_CLICKHOUSE_DATA"        "10Gi"
export_var_with_default "DATASTORE_SIZE_CLICKHOUSE_LOG"         "1Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_ZOOKEEPER"     "default"
export_var_with_default "DATASTORE_SIZE_ZOOKEEPER"              "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_ELASTICSEARCH" "default"
export_var_with_default "DATASTORE_SIZE_ELASTICSEARCH"          "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_KAFKA"         "default"
export_var_with_default "DATASTORE_SIZE_KAFKA"                  "2Gi"
export_var_with_default "DATASTORE_STORAGE_CLASS_KAFKA_ZK"      "default"
export_var_with_default "DATASTORE_SIZE_KAFKA_ZK"               "10Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_POSTGRES"      "default"
export_var_with_default "DATASTORE_SIZE_POSTGRES"               "3Gi"

export_var_with_default DATASTORE_STORAGE_CLASS_SYNTHETICS      "default"
export_var_with_default DATASTORE_SIZE_SYNTHETICS               "5Gi"

export_var_with_default "DATASTORE_STORAGE_CLASS_SPANS"         "azurefile"
export_var_with_default "DATASTORE_SIZE_SPANS"                  "10Gi"

export_var_with_default "INSTANA_OPERATOR_VERSION"              "273.4.0"
export_var_with_default "INSTANA_OPERATOR_IMAGETAG"             "273-4"


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
echo "==========================================================="
echo "Let's do a quick check for the required tools..."
# check kubectl
if is_required_tool_missed "kubectl"; then missed_tools=$((missed_tools+1)); fi
# check Instana kubectl plugin
# if is_required_tool_missed "kubectl-instana"; then missed_tools=$((missed_tools+1)); fi
# check openssl
if is_required_tool_missed "openssl"; then missed_tools=$((missed_tools+1)); fi
# check curl
if is_required_tool_missed "curl"; then missed_tools=$((missed_tools+1)); fi
# check yq
if is_required_tool_missed "yq"; then missed_tools=$((missed_tools+1)); fi
# final check
if [[ $missed_tools > 0 ]]; then
  echo "Abort! There are some required tools missing, please have a check."
  return 2
fi

echo "========: Result"
logme "$color_yellow" "If you don't see any $color_red RED ERRORS $color_end, you're ready to proceed."
logme "$color_yellow" "you may double check the variables exported, by: env | egrep \"DATASTORE_|INSTANA_\""
