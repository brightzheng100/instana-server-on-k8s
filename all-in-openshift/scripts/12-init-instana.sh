#!/bin/bash

# Important Notes:
# This is the "overlay" of <root>/single-node-k8s/scripts/12-init-instana.sh
# Only functions changed will be here for replacement

function exposing-instana-server-servies {
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
