# Instana Server on single-node K8s, step by step

## Spinnig up K8s

### K8s tools: `kubeadm`, `kubectl` and `kubelet`

```sh
# Specify the version
export K8S_VERSION=1.26

# Add K8s repo
cat <<'EOF' | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

# Set SELinux in permissive mode (effectively disabling it)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

sudo dnf install -y kubelet-$K8S_VERSION kubeadm-$K8S_VERSION kubectl-$K8S_VERSION --disableexcludes=kubernetes

# Enable kubelet
sudo systemctl enable kubelet
```

> Note: The `kubelet` is now restarting every few seconds, as it waits in a crashloop for kubeadm to tell it what to do.


### CRI Runtime

```sh
export CRIO_VERSION=1.26
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION/CentOS_8/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.repo
sudo dnf install cri-o -y

# Enable and start cri-o service
sudo systemctl enable crio
sudo systemctl start crio
```

### Bootstrap with `kubeadm`

#### Prerequisites

```sh
# 1. Disable the swap. To make it permanent, update the /etc/fstab and comment/remove the line with swap
#   sudo vi /etc/fstab
#   UUID=0aa6ce7f-b825-4b08-9515-b1e7a2bdb9a9 / ext4 defaults,noatime 0 1
#   UUID=f909ac6c-f5e5-4f9a-874a-8aabecc4f674 /boot ext4 defaults,noatime 0 0
#   #LABEL=SWAP-xvdb1	swap	swap	defaults,nofail	0	0
sudo swapoff -a

# 2. Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# 3. Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
```

#### Bootstrap it

> Important Note: 
> 1. We specify the `service-node-port-range: 443-32767` so that we can bring ports like `443`, `1444` as NodePorts too.
> 2. The reason why we specify the `--pod-network-cidr` is that we're going to use Calico, which defauts to this cidr.

```sh
sudo kubeadm init --config manifests/kubeadm-init-conf.yaml
```

And get ready for access:

```sh
# Copy over the kube config for admin access
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Remove the taint as we have only one node
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### CNI

```sh
# Specify the version
export CALICO_MANIFEST_FILE="https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml"

# Install Calico CNI
kubectl apply -f "${CALICO_MANIFEST_FILE}"
```


## Install Instana

### Tools needed

```sh
# Specify the version
export INSTANA_VERSION="241-3"

# Instana kubectl plugin
# Please visit the doc here: https://www.ibm.com/docs/en/instana-observability/current?topic=premises-instana-kubectl-plug-in#manual-installation, to download the right `kubectl` plugin and install it properly.
curl -sSL --output _wip/kubectl-instana-linux_amd64-release.tar.gz https://self-hosted.instana.io/kubectl/kubectl-instana-linux_amd64-release-${INSTANA_VERSION}.tar.gz
tar -xvf _wip/kubectl-instana-linux_amd64-release.tar.gz -C _wip
sudo mv _wip/kubectl-instana /usr/local/bin/

# yq
curl -sSL --output _wip/yq_linux_amd64 https://github.com/mikefarah/yq/releases/download/v4.31.2/yq_linux_amd64
chmod +x _wip/yq_linux_amd64
sudo mv _wip/yq_linux_amd64 /usr/local/bin/yq
```

We can then verify that -- in my case, as shown below, it's on `241-3` version of Instana:

```sh
$ kubectl instana --version
kubectl-instana version 241-3 (commit=504f3997ef3bd84411972fa4439468b3b4638396, date=2023-02-28T15:35:20+01:00, image=, branch=release)

Minimum required database versions:
elasticsearch       :	Major: 7 	min. Minor: 16
cassandra           :	Major: 4 	min. Minor: 0
clickhouse          :	Major: 22.3 	min. Minor: 2
beeinstana          :	Major: 1 	min. Minor: 160
cockroachdb         :	Major: 21 	min. Minor: 1
kafka               :	Major: 3 	min. Minor: 2
```

### Namespaces

```sh
kubectl apply -f manifests/namespaces.yaml
```

### Storage Provisioner

Here we install Rancher's [Local Path Provisioner](https://github.com/rancher/local-path-provisioner) for simplicity.

```sh
# Specify the root mount point
export DATASTORE_MOUNT_ROOT="/storage"

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.23/deploy/local-path-storage.yaml

cat manifests/local-path-config.yaml | envsubst '$DATASTORE_MOUNT_ROOT' | kubectl apply -f -
```

> Note: the `Local Path Provisioner` actually doesn't support `ReadWriteMany`, so I set the `rawSpans` in [`manifest/core.yaml`](./manifest/core.yaml) with `ReadWriteOnce`, instead of required `ReadWriteMany`, which is fine in single-node K8s.


### Instana Operator

```sh
# Specify environment variables
export INSTANA_AGENT_KEY="<YOUR LICENSE'S AGENT KEY>"

# Installing Cert Manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml

# Wait for cert manager to be ready
sleep 120

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
```


### Instana Datastores

```sh
# Export environment variables
export DATASTORE_SIZE_BEEINSTANA="10Gi"
export DATASTORE_STORAGE_CLASS_BEEINSTANA="local-path"
export DATASTORE_SIZE_CASSANDRA="10Gi"
export DATASTORE_STORAGE_CLASS_CASSANDRA="local-path"
export DATASTORE_SIZE_CLICKHOUSE="10Gi"
export DATASTORE_STORAGE_CLASS_CLICKHOUSE="local-path"
export DATASTORE_SIZE_CLICKHOUSE_ZK="2Gi"
export DATASTORE_STORAGE_CLASS_CLICKHOUSE_ZK="local-path"
export DATASTORE_SIZE_ELASTICSEARCH="10Gi"
export DATASTORE_STORAGE_CLASS_ELASTICSEARCH="local-path"
export DATASTORE_SIZE_KAFKA="2Gi"
export DATASTORE_STORAGE_CLASS_KAFKA="local-path"
export DATASTORE_SIZE_KAFKA_ZK="10Gi"
export DATASTORE_STORAGE_CLASS_KAFKA_ZK="local-path"
export DATASTORE_SIZE_POSTGRES="3Gi"
export DATASTORE_STORAGE_CLASS_POSTGRES="local-path"
export DATASTORE_SIZE_SPANS="10Gi"
export DATASTORE_STORAGE_CLASS_SPANS="local-path"

kubectl apply -f manifests/datastores-secrets.yaml

kubectl create secret docker-registry instana-registry \
  --namespace=instana-datastores \
  --docker-username=_ \
  --docker-password="${INSTANA_AGENT_KEY}" \
  --docker-server=containers.instana.io

envsubst < manifests/datastores-cr.yaml | kubectl apply -f -
```

### secret: image pull secrets

```sh
# Create image pull secrets in both instana-core and instana-units namespaces
for n in {"instana-core","instana-units"}; do
  kubectl create secret docker-registry instana-registry \
    --namespace="${n}" \
    --docker-username=_ \
    --docker-password="${INSTANA_AGENT_KEY}" \
    --docker-server=containers.instana.io
done
```

### secret: instana-core 

```sh
export INSTANA_DOWNLOAD_KEY="<YOUR LICENSE'S DOWNLOAD KEY>"
export INSTANA_SALES_KEY="<YOUR LICENSE'S SALES KEY>"
export INSTANA_ADMIN_USER="admin@instana.local"
export INSTANA_ADMIN_PWD="Passw0rd"
export INSTANA_KEY_PASSPHRASE="Passw0rd"

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
```

### secret: instana-tls

```sh
# Note: the FQDN can be IP, or <IP>.nip.io, or instana.<IP>.nip.io, or real FQDN like instana.example.com
export INSTANA_EXPOSED_FQDN="<YOUR FQDN TO INSTANA UI>"

openssl req -x509 -newkey rsa:2048 -keyout \
  _wip/tls.key -out _wip/tls.crt -days 365 -nodes \
  -subj "/CN=${INSTANA_EXPOSED_FQDN}"

kubectl create secret tls instana-tls --namespace instana-core \
  --cert=_wip/tls.crt --key=_wip/tls.key
kubectl label secret instana-tls app.kubernetes.io/name=instana -n instana-core
```

### secret: tenant0-unit0

```sh
export INSTANA_ADMIN_USER="admin@instana.local"
export INSTANA_ADMIN_PWD="Passw0rd"
export INSTANA_KEY_PASSPHRASE="Passw0rd"

# Prepare unit config file
license="`cat _wip/license.json`" \
  envsubst < manifests/unit-config.yaml > _wip/unit-config.yaml

# Create tenant0-unit0 secret with the config file
# Please note the key must be "config.yaml"
kubectl create secret generic tenant0-unit0 \
  --namespace instana-units \
  --from-file=config.yaml=_wip/unit-config.yaml
```

### Core

```sh
envsubst < manifests/core.yaml | kubectl apply -f -
```

> Note: this step will take a few (~10) minutes for pods to be created in `instana-core` namespace. You may have a check by: `kubectl get pods -n instana-core`.

We should see pods like:

```sh
$ kubectl get pod -n instana-core
NAME                                         READY   STATUS    RESTARTS   AGE
acceptor-6cd57787c9-j2phl                    1/1     Running   0          3m23s
accountant-5985bcfd96-52bkn                  1/1     Running   0          3m23s
appdata-health-aggregator-7fb476cc84-9sr52   1/1     Running   0          3m23s
appdata-health-processor-5cb4547567-ph77v    1/1     Running   0          3m23s
appdata-reader-b4979bf7b-l464g               1/1     Running   0          3m23s
appdata-writer-78bfbf5487-l797w              1/1     Running   0          3m23s
butler-5fcccf94bd-6xqgj                      1/1     Running   0          3m23s
cashier-ingest-594895547c-fqlqv              1/1     Running   0          3m23s
cashier-rollup-554489489b-6sblc              1/1     Running   0          3m23s
eum-acceptor-79f6d6c4fb-cxj5x                1/1     Running   0          3m22s
eum-health-processor-587dc9db-npmvd          1/1     Running   0          3m22s
eum-processor-7668c99485-d2746               1/1     Running   0          3m22s
gateway-d9856675f-fhxwq                      1/1     Running   0          2m29s
groundskeeper-6f95cd7b45-92gr8               1/1     Running   0          3m21s
js-stack-trace-translator-546d48f586-sxhvq   1/1     Running   0          3m21s
serverless-acceptor-7bb59695c4-qj2j4         1/1     Running   0          3m21s
sli-evaluator-df7989c9b-kv6fl                1/1     Running   0          3m21s
tag-processor-59d5d6c7d7-wtwsj               1/1     Running   0          3m21s
tag-reader-b5bb46cb7-qttfd                   1/1     Running   0          3m20s
ui-client-7446d44bdb-hh7mk                   1/1     Running   0          2m29
```

### Unit

```sh
kubectl apply -f manifests/tenant0-unit0.yaml
```

> Note: we use `small` resourceProfile.

```sh
$ kubectl get pod -n instana-units
NAME                                                         READY   STATUS    RESTARTS   AGE
tu-tenant0-unit0-appdata-legacy-converter-6cf758576c-4rd8x   1/1     Running   0          3m27s
tu-tenant0-unit0-appdata-processor-7cc6699bf4-vz89z          1/1     Running   0          3m27s
tu-tenant0-unit0-filler-d59c4c758-zstz4                      1/1     Running   0          3m27s
tu-tenant0-unit0-issue-tracker-7bf767647b-77dpl              1/1     Running   0          3m26s
tu-tenant0-unit0-processor-6759cb6f67-9jxr2                  1/1     Running   0          3m26s
tu-tenant0-unit0-ui-backend-5f786cb6c9-f85jh                 1/1     Running   0          3m26s
```

### Ingress

For simplicity, we expose the services by NodePort.

There are two configurable ports:
- `${INSTANA_EXPOSED_PORT}`, which defauts to port `443`, for gateway; and
- `${INSTANA_EXPOSED_PORT_ACCEPTOR}`, which defaults to port `1444`, for acceptor

```sh
envsubst < manifests/services-with-nodeport.yaml | kubectl apply -f -
```

### Access it

```sh
echo "You should be able to acdess Instana UI by:"
echo " - URL: https://${INSTANA_EXPOSED_FQDN}:${INSTANA_EXPOSED_PORT}"
echo " - USER: ${INSTANA_ADMIN_USER}"
echo " - PASSWORD: ${INSTANA_ADMIN_PWD}"
```

## Issues & Solutions

### unable to connect to initial hosts: Provided username cassandra_user and/or password are incorrect

If you encountered `unable to connect to initial hosts: Provided username cassandra_user and/or password are incorrect`, it's because the Cassandra's user/password hasn't been initialized.

You may either use the default `cassandra/cassandra` like what I did, which has been specified in [`manifests/datastore-secrets.yaml`](./manifests/datastore-secrets.yaml) and [`manifests/core-config.yaml`](./manifests/core-config.yaml); or create your own explictily with necessary changes in abovementioned files and apply them accordingly:

```sh
bash-5.1$ cqlsh default-cassandra.instana-datastores 9042 -u cassandra -p cassandra
cassandra@cqlsh> LIST ROLES;
cassandra@cqlsh> CREATE ROLE cassandra_user WITH PASSWORD = 'cassandra_pass' 
    AND SUPERUSER = true 
    AND LOGIN = true;
cassandra@cqlsh> exit
bash-5.1$ cqlsh default-cassandra.instana-datastores 9042 -u cassandra_user -p cassandra_pass
```

## Some outputs for reference only

### Bootstrapping K8s

```log
sudo kubeadm init --pod-network-cidr=192.168.0.0/16
[init] Using Kubernetes version: v1.26.2
[preflight] Running pre-flight checks
	[WARNING FileExisting-tc]: tc not found in system path
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action in beforehand using 'kubeadm config images pull'
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [itz-550004ghs4-df16.dte.demo.ibmcloud.com kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 169.61.6.184]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [itz-550004ghs4-df16.dte.demo.ibmcloud.com localhost] and IPs [169.61.6.184 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [itz-550004ghs4-df16.dte.demo.ibmcloud.com localhost] and IPs [169.61.6.184 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests". This can take up to 4m0s
[apiclient] All control plane components are healthy after 8.004256 seconds
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Skipping phase. Please see --upload-certs
[mark-control-plane] Marking the node itz-550004ghs4-df16.dte.demo.ibmcloud.com as control-plane by adding the labels: [node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node itz-550004ghs4-df16.dte.demo.ibmcloud.com as control-plane by adding the taints [node-role.kubernetes.io/control-plane:NoSchedule]
[bootstrap-token] Using token: 4gs2d6.jsui7fevkaq9yv6z
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] Configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] Configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 169.61.6.184:6443 --token 4gs2d6.jsui7fevkaq9yv6z \
	--discovery-token-ca-cert-hash sha256:28b9172f8a9ddd024baa38231108c8f947762df8e317xxxxxxxxxxxxxxxx
```

### Installing Calico CNI

```log
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
poddisruptionbudget.policy/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
serviceaccount/calico-node created
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/bgppeers.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/blockaffinities.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/caliconodestatuses.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/clusterinformations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/felixconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworksets.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/hostendpoints.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamblocks.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamconfigs.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamhandles.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ippools.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipreservations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/kubecontrollersconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networksets.crd.projectcalico.org created
clusterrole.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrole.rbac.authorization.k8s.io/calico-node created
clusterrolebinding.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrolebinding.rbac.authorization.k8s.io/calico-node created
daemonset.apps/calico-node created
deployment.apps/calico-kube-controllers created
```

### kubectl instana operator apply

```sh
$ kubectl instana operator apply \
  --namespace=instana-operator \
  --values manifests/operator-values.yaml

namespaces/instana-operator updated
serviceaccounts/instana-operator created
serviceaccounts/instana-operator-webhook created
customresourcedefinitions/cores.instana.io created
customresourcedefinitions/datastores.instana.io created
customresourcedefinitions/units.instana.io created
clusterroles/instana-operator created
clusterroles/instana-operator-webhook created
clusterrolebindings/instana-operator created
clusterrolebindings/instana-operator-webhook created
roles/instana-operator-leader-election created
rolebindings/instana-operator-leader-election created
services/instana-operator-webhook created
deployments/instana-operator created
deployments/instana-operator-webhook created
certificates/instana-operator-webhook created
issuers/instana-operator-webhook created
validatingwebhookconfigurations/instana-operator-webhook-validating created
```
