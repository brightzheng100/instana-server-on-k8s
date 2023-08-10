# Deploying Instana on Kubernetes Cluster

**!!!WIP!!!**

This repository guides you through how to set up Instana on an CNCF-certified / OSS Kubernetes cluster, with 3rd party Operators for building the datastore components.

Tested environments and the Instana version used:

- Kubernetes v1.26.x -- it should work in other Kubernetes versions.
- on Instana version `253-1`. Please note that the `kubectl instana` plugin's version determines the Instana version you will install.

Please note that there are a couple of beta features turned on by default, as of writing:
- BeeInstana
- Apdex
- Logging
- Automation / Actioin Framework

You may turn off some of them to save some resources, if you want.


## Prerequisites

### The Tools

A series of tools will be needed, on the laptop or the VM where you run the scripts, which include:
- `kubectl`
- `openssl`
- `curl`
- [`yq`](https://github.com/mikefarah/yq) -- do use the right tool with the link provided.
- **Instana kubectl plugin**. Please visit the doc [here](https://www.ibm.com/docs/en/instana-observability/current?topic=installing-instana-kubectl-plug-in) to download the right `kubectl` plugin, with the **desired version**, and install it properly. Verify and make sure it works properly:

```sh
$ kubectl instana --version
kubectl-instana version 253-1 (commit=63d2ba7e8fd09943f2c2da539a4ac5cfdb3f2852, date=2023-07-28T16:38:27+02:00)

Minimum required database versions:

kafka               :	Major: 3 	min. Minor: 2
elasticsearch       :	Major: 7 	min. Minor: 16
cassandra           :	Major: 4 	min. Minor: 0
clickhouse          :	Major: 23.3 	min. Minor: 2
beeinstana          :	Major: 1 	min. Minor: 160
postgres            :	Major: 15 	min. Minor: 0
```

### The Kubernetes Cluster

Any CNCF-certified Kubernetes should just work -- and I tried IKS, AKS etc., nothing was different from the deployment experience perspective.

Please note that the CSI-compliant storage is very important while deploying Instana on Kubernetes.

Basically we need two types of storage:
- Block storage for almost everything of the datastore components;
- `ReadWriteMany` supported file storage for raw spans, which can be set by `DATASTORE_STORAGE_CLASS_SPANS`, in a real-world multi-node cluster!


## The TL'DR Guide

You may run it in your laptop (e.g. MacBook), or a Linux machine, either way should just work as long as you can access the Kubernetes cluster and the required tools are installed.

**And, make sure you've already logged into Kubernetes cluster with ClusterAdmin permission.**

### 0. Prepare

We need to decide how the ingress works first in your Kubernetes cluster.

Let me use AKS as an example, I use Nginx Ingress, like this:

```sh
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --create-namespace \
  --namespace ingress-controller \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

And we should see something like:

```sh
$ kubectl get svc -n ingress-controller
NAME                                 TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   10.0.117.152   20.26.139.84   80:30562/TCP,443:31322/TCP   2m2s
ingress-nginx-controller-admission   ClusterIP      10.0.164.13    <none>         443/TCP                      2m2s
```

And I'd assume we're going to use Ingress in our case.

Then:

```sh
# Clone the repo
git clone https://github.com/brightzheng100/instana-server-on-k8s.git
cd instana-server-on-k8s/all-in-k8s

# Make a directory for hosting some working files, which will be ignored by Git
mkdir _wip

# Export required environment variables
export INSTANA_EXPOSED_FQDN="<THE FQDN, OR IP, e.g. 20.26.139.84.nip.io>"
export INSTANA_AGENT_KEY="<THE LICENSE'S AGENT KEY>"
export INSTANA_DOWNLOAD_KEY="<THE LICENSE'S DOWNLOAD KEY>"
export INSTANA_SALES_KEY="<THE LICENSE'S SALES KEY>"
```

And, quite importantly, you have to take care of the StorageClasses for a list of persistence components.
- For normal datastore components, like `DATASTORE_STORAGE_CLASS_CASSANDRA`, use block storage;
- For `DATASTORE_STORAGE_CLASS_SPANS`, you must set the StorageClass that supports `ReadWriteMany` in a real-world multi-node cluster!

So get ready and export them accordingly to fit into your Kubernetes context -- here I use `azurefile` as the file-based storage for `DATASTORE_STORAGE_CLASS_SPANS`, while `default` for the rest, both are available in AKS. You may check it out by running: `kubectl get storageclass`.

```sh
export DATASTORE_STORAGE_CLASS_BEEINSTANA="default"
export DATASTORE_SIZE_BEEINSTANA="10Gi"

export DATASTORE_STORAGE_CLASS_CASSANDRA="default"
export DATASTORE_SIZE_CASSANDRA="10Gi"

export DATASTORE_STORAGE_CLASS_CLICKHOUSE="default"
export DATASTORE_SIZE_CLICKHOUSE_DATA="10Gi"
export DATASTORE_SIZE_CLICKHOUSE_LOG="1Gi"

export DATASTORE_STORAGE_CLASS_ZOOKEEPER="default"
export DATASTORE_SIZE_ZOOKEEPER="10Gi"

export DATASTORE_STORAGE_CLASS_ELASTICSEARCH="default"
export DATASTORE_SIZE_ELASTICSEARCH="10Gi"

export DATASTORE_STORAGE_CLASS_KAFKA="default"
export DATASTORE_SIZE_KAFKA="2Gi"
export DATASTORE_STORAGE_CLASS_KAFKA_ZK="default"
export DATASTORE_SIZE_KAFKA_ZK="10Gi"

export DATASTORE_STORAGE_CLASS_POSTGRES="default"
export DATASTORE_SIZE_POSTGRES="3Gi"

export DATASTORE_STORAGE_CLASS_SPANS="azurefile"
export DATASTORE_SIZE_SPANS="10Gi"
```

Optionally, you may export more environment variables to influence the installation if that makes sense -- the process will respect the desired changes you want to make.

Please refer to [`scripts/13-init-vars.sh`](./scripts/13-init-vars.sh) for the potential environment variables that can be exported.

<details>
  <summary>Click here to show some examples.</summary>
  
  For example, to change the default Instana console login password, do something like this:

  ```sh
  export INSTANA_ADMIN_PWD=MyCoolPassword
  ```

</details>


Till now, the preparation has been done, and let's get started!


### 1. Init it

```sh
source 1-init-all.sh
```

As long as no RED LINES highlighted in the output, you're good to proceed.


### 2. Install Instana

If you want to install Instana in one shot, do this:

```sh
./2-install-instana.sh
```

But, I'd highly recommend you do it step by step so you have better chance to troubleshoot.
So, run below commands, well, custom functions actually, one by one instead.

<details>
  <summary>Click here to show the step-by-step commands.</summary>

  ```sh
  creating-namespaces

  installing-cert-manager
  # check before proceeding: wait 5 mins for expected 3 pods
  check-namespaced-pod-status-and-keep-displaying-info "cert-manager" 5 3 "kubectl get pod -n cert-manager"

  installing-datastore-kafka
  installing-datastore-elasticsearch
  installing-datastore-postgres
  installing-datastore-cassandra
  installing-datastore-clickhouse

  installing-beeinstana
  # check before proceeding: wait 10 mins for expected 4 pods
  check-namespaced-pod-status-and-keep-displaying-info "instana-beeinstana" 10 4 "kubectl get pod -n instana-beeinstana"

  installing-instana-operator
  # check before proceeding: wait 8 mins for expected 2 pods
  check-namespaced-pod-status-and-keep-displaying-info "instana-operator" 8 2 "kubectl get pod -n instana-operator"

  installing-instana-server-secret-image-pullsecret
  installing-instana-server-secret-instana-core
  installing-instana-server-secret-instana-tls
  installing-instana-server-secret-tenant0-unit0

  installing-instana-server-core
  # check before proceeding: wait 20 mins for expected 22 pods
  check-namespaced-pod-status-and-keep-displaying-info "instana-core" 20 22 "kubectl get pod -n instana-core"

  installing-instana-server-unit
  # check before proceeding: wait 10 mins for expected 6 pods
  check-namespaced-pod-status-and-keep-displaying-info "instana-units" 10 6 "kubectl get pod -n instana-units"

  exposing-instana-server-services
  ```
  
</details>


Please note that multitenancy is fully supported when Instana is deployed on Kubernetes, as long as we have sufficient resources / worker nodes. What we need to do is to deploy multiple `Unit` objects, say `tenant-dev` and `tenant-prod`, like what we did for `tenant0-unit0`.


### 3. How to access?

Once you've gone through all above steps successfully, the Instana should have been deployed.
Now, you can print out the access info:

```sh
how-to-access-instana
```
