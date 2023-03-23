#!/bin/bash

### Installing Instana Kubectl plugin
function installing-tools {
  echo "----> installing-tools"

  # Instana kubectl plugin
  logme "$color_green" "Instana kubectl plugin..."
  curl -sSL --output _wip/kubectl-instana-linux_amd64-release.tar.gz https://self-hosted.instana.io/kubectl/kubectl-instana-linux_amd64-release-${INSTANA_VERSION}.tar.gz
  tar -xvf _wip/kubectl-instana-linux_amd64-release.tar.gz -C _wip
  sudo mv _wip/kubectl-instana /usr/local/bin/

  logme "$color_green" "Instana kubectl plugin - DONE"

  # yq
  logme "$color_green" "yq..."
  curl -sSL --output _wip/yq_linux_amd64 https://github.com/mikefarah/yq/releases/download/v4.31.2/yq_linux_amd64
  chmod +x _wip/yq_linux_amd64
  sudo mv _wip/yq_linux_amd64 /usr/local/bin/yq
  
  logme "$color_green" "yq - DONE"
}

### Creating namespaces
function creating-namespaces {
  echo "----> creating-namespaces"

  kubectl apply -f manifests/namespaces.yaml
  logme "$color_green" "DONE"
}

### Installing local-path-provisioner
function installing-local-path-provisioner {
  echo "----> installing-local-path-provisioner"

  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.23/deploy/local-path-storage.yaml

  cat manifests/local-path-config.yaml |  envsubst '$DATASTORE_MOUNT_ROOT' | kubectl apply -f -

  logme "$color_green" "DONE"
}

### Installing Cert Manager
function installing-cert-manager {
  echo "----> installing-cert-manager"

  # Installing Cert Manager
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml

  logme "$color_green" "DONE"
}

### Installing Instana Operator
function installing-instana-operator {
  echo "----> installing-instana-operator"

  # Create the secret
  kubectl create secret docker-registry instana-registry \
    --namespace=instana-operator \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}" \
    --docker-server=containers.instana.io

  # Apply the Instana Operator
  kubectl instana operator apply \
    --namespace=instana-operator \
    --values manifests/operator-values.yaml

  logme "$color_green" "DONE"
}

### Installing Instana Datastores
function installing-instana-datastores {
  echo "----> installing-instana-datastores"

  kubectl apply -f manifests/datastores-secrets.yaml

  kubectl create secret docker-registry instana-registry \
    --namespace=instana-datastores \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}" \
    --docker-server=containers.instana.io

  envsubst < manifests/datastores-cr.yaml | kubectl apply -f -

  logme "$color_green" "DONE"
}

function installing-instana-server-components-secret-image-pullsecret {
  echo "----> installing-instana-server-components-image-pullsecret"

  # Create image pull secrets in both namespaces
  for n in {"instana-core","instana-units"}; do
    kubectl create secret docker-registry instana-registry \
      --namespace="${n}" \
      --docker-username=_ \
      --docker-password="${INSTANA_AGENT_KEY}" \
      --docker-server=containers.instana.io
  done

  logme "$color_green" "DONE"
}

function installing-instana-server-components-secret-instana-core {
  echo "----> installing-instana-server-components-secret-instana-core"

  # Generate and download the license file based on the sales key
  kubectl instana license download \
    --sales-key "${INSTANA_SALES_KEY}" \
    --filename _wip/license.json

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
  cp manifests/core-config.yaml _wip/core-config.yaml && \
  yq -i "
    .adminPassword = \"${INSTANA_ADMIN_PWD}\" |
    .dhParams = \"${dhparams}\" |
    .downloadKey = \"${INSTANA_DOWNLOAD_KEY}\" |
    .salesKey = \"${INSTANA_SALES_KEY}\" |
    .serviceProviderConfig.keyPassword = \"${sp_keyPassword}\" |
    .serviceProviderConfig.pem = \"${sp_pem}\"
  " _wip/core-config.yaml

  # Create instana-core secret with the config file
  # Please note the key must be "config.yaml"
  #kubectl delete secret/instana-core --namespace instana-core
  kubectl create secret generic instana-core \
    --namespace instana-core \
    --from-file=config.yaml=_wip/core-config.yaml
  
  logme "$color_green" "DONE"
}

function installing-instana-server-components-secret-instana-tls {
  echo "----> installing-instana-server-components-secret-instana-tls"

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

function installing-instana-server-components-secret-tenant0-unit0 {
  echo "----> installing-instana-server-components-secret-tenant0-unit0"

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

function installing-instana-server-components-core {
  echo "----> installing-instana-server-components-core"

  # Create the `instana-core` CR object
  envsubst < manifests/core.yaml | kubectl apply -f -
  
  logme "$color_green" "DONE"
}

function installing-instana-server-components-unit {
  echo "----> installing-instana-server-components-unit"

  # Create unit object
  kubectl apply -f manifests/tenant0-unit0.yaml
  
  logme "$color_green" "DONE"
}

function exposing-instana-server-servies {
  echo "----> exposing-instana-server-servies"

  # Expose services by NodePort
  envsubst < manifests/services-with-nodeport.yaml | kubectl apply -f -
  
  logme "$color_green" "DONE"
}

function how-to-access-instana {
  echo "#################################################"
  echo "You should be able to acdess Instana UI by:"
  echo " - URL: https://${INSTANA_EXPOSED_FQDN}:${INSTANA_EXPOSED_PORT}"
  echo " - USER: ${INSTANA_ADMIN_USER}"
  echo " - PASSWORD: ${INSTANA_ADMIN_PWD}"
}
