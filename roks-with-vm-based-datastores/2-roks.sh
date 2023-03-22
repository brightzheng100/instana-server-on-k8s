#!/bin/bash

### Some utils
function is_required_tool_missed {
    echo "Checking required tool: $1 ... "
    if [ -x "$(command -v $1)" ]; then
        echo "installed"
        false
    else
        echo "NOT installed"
        true
    fi
}

### Installing Instana Operator
function installing-instana-operator {
  echo "----> installing-instana-operator"

  # Installing Cert Manager
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml

  # Wait for cert manager to be ready
  echo "----> wait for 120 seconds"
  sleep 120
    
  # Create namespace for Instana Operator
  kubectl create namespace instana-operator

  # Create the secret
  kubectl create secret docker-registry instana-registry \
    --namespace=instana-operator \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}" \
    --docker-server=containers.instana.io

  # Create a _wip folder to host temp files which will be ignored by Git
  mkdir _wip

  # Prepare necessary customization
  cat > _wip/instana-operator-values.yaml <<EOF
imagePullSecrets:
  - name: instana-registry
EOF

  # Apply the Instana Operator
  kubectl instana operator apply \
    --namespace=instana-operator \
    --values _wip/instana-operator-values.yaml
}



### Installing Instana Server Components
function installing-instana-server-components-namespaces {
  echo "----> installing-instana-server-components-namespaces"

  # Create two namespaces:
  # - instana-core: for Instana's foundational components
  # - instana-units: for Instana's tenants and units
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: instana-core
  labels:
    app.kubernetes.io/name: instana-core
---
apiVersion: v1
kind: Namespace
metadata:
  name: instana-units
  labels:
    app.kubernetes.io/name: instana-units
EOF
}

function installing-instana-server-components-image-pullsecret {
  echo "----> installing-instana-server-components-image-pullsecret"

  # Create image pull secrets in both namespaces
  for n in {"instana-core","instana-units"}; do
    kubectl create secret docker-registry instana-registry \
      --namespace="${n}" \
      --docker-username=_ \
      --docker-password="${INSTANA_AGENT_KEY}" \
      --docker-server=containers.instana.io
  done
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

  cat > _wip/instana-core-config.yaml <<EOF
# The initial password for the admin user
adminPassword:
# Diffie-Hellman parameters to use
dhParams:
# The download key you received from us
downloadKey:
# The sales key you received from us
salesKey:
# Seed for creating crypto tokens. Pick a random 12 char string
tokenSecret: mytokensecret
# Configuration for raw spans storage
#rawSpansStorageConfig:
  # Required if using S3 or compatible and credentials should be configured.
  # Not required if using IRSA on EKS.
  #s3Config:
    #accessKeyId: ...
    #secretAcessKey: ...
  # Required if using Google Cloud Storage and credentials should be configured.
  # Not required if using GKE with workload identity.
  #gcloudConfig:
    #serviceAccountKey: ...
# SAML/OIDC configuration
serviceProviderConfig:
  # Password for the key/cert file
  keyPassword: "${INSTANA_KEY_PASSPHRASE}"
  # The combined key/cert file
  pem:
# Required if a proxy is configured that needs authentication
#proxyConfig:
  # Proxy user
  #user: myproxyuser
  # Proxy password
  #password: my proxypassword
#emailConfig:
  # Required if SMTP is used for sending e-mails and authentication is required
  #smtpConfig:
  #  user: mysmtpuser
  #  password: mysmtppassword
  # Required if using for sending e-mail and credentials should be configured.
  # Not required if using IRSA on EKS.
  #sesConfig:
  #  accessKeyId: ...
  #  secretAcessKey: ...
EOF

  # Prepare the core config file
  dhparams="`cat _wip/dhparams.pem`" && \
  sp_keyPassword="${INSTANA_KEY_PASSPHRASE}" && \
  sp_pem="`cat _wip/sp.pem`" && \
  yq -i "
    .adminPassword = \"${INSTANA_ADMIN_PWD}\" |
    .dhParams = \"${dhparams}\" |
    .downloadKey = \"${INSTANA_DOWNLOAD_KEY}\" |
    .salesKey = \"${INSTANA_SALES_KEY}\" |
    .serviceProviderConfig.keyPassword = \"${sp_keyPassword}\" |
    .serviceProviderConfig.pem = \"${sp_pem}\"
  " _wip/instana-core-config.yaml

  # Create instana-core secret with the config file
  # Please note the key must be "config.yaml"
  kubectl create secret generic instana-core \
    --namespace instana-core \
    --from-file=config.yaml=_wip/instana-core-config.yaml
}

function installing-instana-server-components-secret-instana-tls {
  echo "----> installing-instana-server-components-secret-instana-tls"

  openssl req -x509 -newkey rsa:2048 -keyout \
    _wip/tls.key -out _wip/tls.crt -days 365 -nodes \
    -subj "/CN=*.containers.appdomain.cloud"

  kubectl create secret tls instana-tls --namespace instana-core \
    --cert=_wip/tls.crt --key=_wip/tls.key
  kubectl label secret instana-tls app.kubernetes.io/name=instana -n instana-core
}

function installing-instana-server-components-secret-tenant0-unit0 {
  echo "----> installing-instana-server-components-secret-tenant0-unit0"

  # Prepare unit config file
  license="`cat _wip/license.json`" && \
  cat > _wip/instana-unit-config.yaml <<EOF
# The initial user of this tenant unit with admin role, default admin@instana.local.
# Must be a valid e-maiol address.
# NOTE:
# This only applies when setting up the tenant unit.
# Changes to this value won't have any effect.
initialAdminUser: ${INSTANA_ADMIN_USER}
# The initial admin password.
# NOTE:
# This is only used for the initial tenant unit setup.
# Changes to this value won't have any effect.
initialAdminPassword: ${INSTANA_ADMIN_PWD}
# The Instana license. Can be a plain text string or a JSON array encoded as string.
# This would also work: '["mylicensestring"]'
license: '${license}'
# A list of agent keys. Specifying multiple agent keys enables gradually rotating agent keys.
agentKeys:
  - ${INSTANA_AGENT_KEY}
EOF

  # Create tenant0-unit0 secret with the config file
  # Please note the key must be "config.yaml"
  kubectl create secret generic tenant0-unit0 \
    --namespace instana-units \
    --from-file=config.yaml=_wip/instana-unit-config.yaml
}

function installing-instana-server-components-pvc-spans {
  echo "----> installing-instana-server-components-pvc-spans"

  oc apply -f - << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: spans-volume-claim
  namespace: instana-core
  labels:
    app.kubernetes.io/component: appdata-writer
    app.kubernetes.io/name: instana
    app.kubernetes.io/part-of: core
    instana.io/group: service
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 2Gi
  storageClassName: ${SPANS_STORAGE_CLASS}
  volumeMode: Filesystem
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: appdata-writer
  namespace: instana-core
  labels:
    app.kubernetes.io/component: appdata-writer
    app.kubernetes.io/name: instana
    app.kubernetes.io/part-of: core
    instana.io/group: service
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 2Gi
  storageClassName: ${SPANS_STORAGE_CLASS}
  volumeMode: Filesystem
EOF
}

function installing-instana-server-components-core {
  echo "----> installing-instana-server-components-core"

  # Create the `instana-core` CR object
  BASE_DOMAIN="`kubectl get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.domain}'`" && \
  kubectl apply -f - <<EOF
apiVersion: instana.io/v1beta2
kind: Core
metadata:
  name: instana-core
  namespace: instana-core
spec:
  agentAcceptorConfig:
    # Host for the agent acceptor. eg: agent.api.<your-subhost>.cp.fyre.ibm.com
    host: "agent.instana.${BASE_DOMAIN}"
    port: 443
  # Base domain for Instana. eg: api.<your-subhost>.cp.fyre.ibm.com
  baseDomain: "instana.${BASE_DOMAIN}"
  componentConfigs:
    - name: acceptor
      replicas: 1
  datastoreConfigs:
    cassandraConfigs:
      - hosts:
          - ${INSTANA_DATASTORE_HOST_FQDN}
        ports:
          - name: tcp
            port: 9042
    cockroachdbConfigs:
      - hosts:
          - ${INSTANA_DATASTORE_HOST_FQDN}
        ports:
          - name: tcp
            port: 26257
    clickhouseConfigs:
      - hosts:
          - ${INSTANA_DATASTORE_HOST_FQDN}
        ports:
          - name: tcp
            port: 9000
          - name: http
            port: 8123
    elasticsearchConfig:
      hosts:
        - ${INSTANA_DATASTORE_HOST_FQDN}
      ports:
        - name: tcp
          port: 9300
        - name: http
          port: 9200
    kafkaConfig:
      hosts:
        - ${INSTANA_DATASTORE_HOST_FQDN}
      ports:
        - name: tcp
          port: 9092
  emailConfig:
    smtpConfig:
      from: test@example.com
      host: example.com
      port: 465
      useSSL: false
  imageConfig:
    registry: containers.instana.io
  rawSpansStorageConfig:
    pvcConfig:
      resources:
        requests:
          storage: 2Gi
      storageClassName: "${SPANS_STORAGE_CLASS}"  # Note: Must support RWX
  resourceProfile: small
  imagePullSecrets:
    - name: instana-registry
  componentConfigs:
    - name: gateway
      properties:
        - name: nginx.http.server_names_hash_bucket_size
          value: "256" # This is important when FQDN is long, default 128
EOF
}

function installing-instana-server-components-unit {
  echo "----> installing-instana-server-components-unit"

  # Create unit object
  kubectl apply -f - <<EOF
apiVersion: instana.io/v1beta2
kind: Unit
metadata:
  namespace: instana-units
  name: tenant0-unit0
spec:
  # Must refer to the name of the Core object we created above
  coreName: instana-core

  # Must refer to the namespace that the associated Core object we created above
  coreNamespace: instana-core

  # The name of the tenant
  tenantName: tenant0

  # The name of the unit within the tenant
  unitName: unit0

  # The same rules apply as for Cores. May be ommitted. Default is 'medium'
  resourceProfile: medium
EOF
}

function installing-instana-server-components-routes {
  echo "----> installing-instana-server-components-routes"

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
}

## No more required as we're using dummy .nip.io FQDN
function installing-instana-server-components-patches-for-core {
  echo "----> installing-instana-server-components-patches-for-core"

  # The patch string
  local patch_string="[
            {\"op\":\"add\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":[{\"hostnames\":[\"${INSTANA_DATASTORE_HOST_FQDN}\"],\"ip\":\"${INSTANA_DATASTORE_HOST_FQDN}\"}]}
          ]"

  # Acceptor
  kubectl patch deployment/acceptor -n instana-core --type "json" -p "${patch_string}"

  # appdata-health-aggregator
  kubectl patch deployment/appdata-health-aggregator -n instana-core --type "json" -p "${patch_string}"

  # appdata-health-processor
  kubectl patch deployment/appdata-health-processor -n instana-core --type "json" -p "${patch_string}"

  # appdata-reader
  kubectl patch deployment/appdata-reader -n instana-core --type "json" -p "${patch_string}"

  # appdata-writer
  kubectl patch deployment/appdata-writer -n instana-core --type "json" -p "${patch_string}"

  # butler
  kubectl patch deployment/butler -n instana-core --type "json" -p "${patch_string}"

  # cashier-ingest
  kubectl patch deployment/cashier-ingest -n instana-core --type "json" -p "${patch_string}"

  # eum-acceptor
  kubectl patch deployment/eum-acceptor -n instana-core --type "json" -p "${patch_string}"

  # eum-health-processor
  kubectl patch deployment/eum-health-processor -n instana-core --type "json" -p "${patch_string}"

  # eum-processor
  kubectl patch deployment/eum-processor -n instana-core --type "json" -p "${patch_string}"

  # groundskeeper
  kubectl patch deployment/groundskeeper -n instana-core --type "json" -p "${patch_string}"

  # js-stack-trace-translator
  kubectl patch deployment/js-stack-trace-translator -n instana-core --type "json" -p "${patch_string}"

  # serverless-acceptor
  kubectl patch deployment/serverless-acceptor -n instana-core --type "json" -p "${patch_string}"

  # serverless-acceptor
  kubectl patch deployment/serverless-acceptor -n instana-core --type "json" -p "${patch_string}"
}

## No more required as we're using dummy .nip.io FQDN
function installing-instana-server-components-patches-for-units {
  echo "----> installing-instana-server-components-patches-for-units"
  
  # The patch string
  local patch_string="[
            {\"op\":\"add\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":[{\"hostnames\":[\"${INSTANA_DATASTORE_HOST_FQDN}\"],\"ip\":\"${INSTANA_DATASTORE_HOST_FQDN}\"}]}
          ]"

  # tu-tenant0-unit0-appdata-legacy-converter
  kubectl patch deployment/tu-tenant0-unit0-appdata-legacy-converter -n instana-units --type "json" -p "${patch_string}"

  # tu-tenant0-unit0-appdata-processor
  kubectl patch deployment/tu-tenant0-unit0-appdata-processor -n instana-units --type "json" -p "${patch_string}"

  # tu-tenant0-unit0-filler
  kubectl patch deployment/tu-tenant0-unit0-filler -n instana-units --type "json" -p "${patch_string}"

  # tu-tenant0-unit0-issue-tracker
  kubectl patch deployment/tu-tenant0-unit0-issue-tracker -n instana-units --type "json" -p "${patch_string}"

  # tu-tenant0-unit0-processor
  kubectl patch deployment/tu-tenant0-unit0-processor -n instana-units --type "json" -p "${patch_string}"

  # tu-tenant0-unit0-ui-backend
  kubectl patch deployment/tu-tenant0-unit0-ui-backend -n instana-units --type "json" -p "${patch_string}"
}

function how-to-access-instana-on-roks {
  local url="$( oc get route -n instana-core instana-gateway -o jsonpath='{.spec.host}' )"

  echo "You should be able to acdess Instana UI by:"
  echo " - URL: https://${url}"
  echo " - USER: ${INSTANA_ADMIN_USER}"
  echo " - PASSWORD: ${INSTANA_ADMIN_PWD}"
}

############################################################

if [ -z "${INSTANA_AGENT_KEY}" ] | \
   [ -z "${INSTANA_DOWNLOAD_KEY}" ] | \
   [ -z "${INSTANA_SALES_KEY}" ] | \
   [ -z "${INSTANA_ADMIN_USER}" ] | \
   [ -z "${INSTANA_ADMIN_PWD}" ] | \
   [ -z "${INSTANA_KEY_PASSPHRASE}" ] | \
   [ -z "${SPANS_STORAGE_CLASS}" ] | \
   [ -z "${INSTANA_DATASTORE_HOST_FQDN}" ]; then 
  echo "ERROR: You must export ALL required variables prior to run the command. For example"
  echo "==========================================================="
  echo "export INSTANA_AGENT_KEY=xxxxxxxxxxxxx"
  echo "export INSTANA_DOWNLOAD_KEY=xxxxxxxxxxxxxxxxx"
  echo "export INSTANA_SALES_KEY=xxxxxxxxxxxxxxxx"
  echo "export INSTANA_ADMIN_USER=admin@instana.local"
  echo "export INSTANA_ADMIN_PWD=Passw0rd"
  echo "export INSTANA_KEY_PASSPHRASE=Passw0rd"
  echo "export SPANS_STORAGE_CLASS=ibmc-file-gold-gid"
  echo "export INSTANA_DATASTORE_HOST_FQDN=168.1.53.248.nip.io"
  return 1
fi

missed_tools=0
echo "==========================================================="
echo "Let's do a quick check for required tools..."
# check oc
if is_required_tool_missed "oc"; then missed_tools=$((missed_tools+1)); fi
# check kubectl
if is_required_tool_missed "kubectl"; then missed_tools=$((missed_tools+1)); fi
# check yq
if is_required_tool_missed "yq"; then missed_tools=$((missed_tools+1)); fi
# check openssl
if is_required_tool_missed "openssl"; then missed_tools=$((missed_tools+1)); fi
# final check
if [[ $missed_tools > 0 ]]; then
  echo "Abort! There are some required tools missing, please have a check."
  return 2
fi

## Display variables
echo "==========================================================="
echo "----> INSTANA_AGENT_KEY=${INSTANA_AGENT_KEY}"
echo "----> INSTANA_DOWNLOAD_KEY=${INSTANA_DOWNLOAD_KEY}"
echo "----> INSTANA_SALES_KEY=${INSTANA_SALES_KEY}"
echo "----> INSTANA_ADMIN_USER=${INSTANA_ADMIN_USER}"
echo "----> INSTANA_ADMIN_PWD=${INSTANA_ADMIN_PWD}"
echo "----> INSTANA_KEY_PASSPHRASE=${INSTANA_KEY_PASSPHRASE}"
echo "----> SPANS_STORAGE_CLASS=${SPANS_STORAGE_CLASS}"
echo "----> INSTANA_DATASTORE_HOST_FQDN=${INSTANA_DATASTORE_HOST_FQDN}"

## Let's orchestrate the process here
# installing-instana-operator
# installing-instana-server-components-namespaces
# installing-instana-server-components-image-pullsecret
# installing-instana-server-components-secret-instana-core
# installing-instana-server-components-secret-instana-tls
# installing-instana-server-components-secret-tenant0-unit0
# installing-instana-server-components-pvc-spans
# installing-instana-server-components-core
# installing-instana-server-components-unit
# installing-instana-server-components-routes
echo "==========================================================="
echo "----> NOW IT'S READY TO ROCK!"
echo "----> Note: even you may run below functions in one shot, I'd highly recommend you run them one by one:"
echo "==========================================================="
echo "installing-instana-operator"
echo "installing-instana-server-components-namespaces"
echo "installing-instana-server-components-image-pullsecret"
echo "installing-instana-server-components-secret-instana-core"
echo "installing-instana-server-components-secret-instana-tls"
echo "installing-instana-server-components-secret-tenant0-unit0"
echo "installing-instana-server-components-pvc-spans"
echo "installing-instana-server-components-core"
echo "installing-instana-server-components-unit"
echo "installing-instana-server-components-routes"

echo "==========================================================="
echo "----> Once it's fully ready, try this command to see how to access it:"
echo "how-to-access-instana-on-roks"

