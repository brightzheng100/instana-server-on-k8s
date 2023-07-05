#!/bin/bash

# Important Notes:
# This is the "overlay" of <root>/single-node-k8s/scripts/12-init-instana.sh
# Only functions changed will be here for replacement

function exposing-instana-server-servies {
  echo "----> exposing-instana-server-servies"

  # Create ingress
  envsubst < manifests/ingress.yaml | kubectl apply -f -

  logme "$color_green" "DONE"
}

function how-to-access-instana {
  local url="$( oc get route -n instana-core instana-gateway -o jsonpath='{.spec.host}' )"

  echo "You should be able to acdess Instana UI by:"
  echo " - URL: https://${url}"
  echo " - USER: ${INSTANA_ADMIN_USER}"
  echo " - PASSWORD: ${INSTANA_ADMIN_PWD}"
}
