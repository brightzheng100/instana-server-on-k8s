# Deploying Instana on OpenShift Cluster

This repository guides you through how to set up Instana on an OpenShift cluster, with 3rd party Operators for building the datastore components.

Latest review on 08 Jan 2024, with:

- Red Hat OpenShift Container Platform (OCP) v4.12 -- it should work in other/newer OCP v4.x versions.
- Instana version `261-2`.

Please note that there are quite some extra configurable features turned on by default, as of writing:
- BeeInstana
- Logging (beta)
- Automation / Action Framework (beta)
- Synthetic Monitoring (beta)

You may turn off some of them to save some resources, if you want, by updating [`core.yaml`](./manifests/core.yaml)'s **featureFlags**.

For the complete configurable features, please refer to official doc [here](https://www.ibm.com/docs/en/instana-observability/current?topic=openshift-enabling-optional-features).


## Prerequisites

### The Tools

A series of tools will be needed, on the laptop or the VM where you run the scripts, which include:
- `oc`
- `kubectl`
- `openssl`
- `curl`
- [`yq`](https://github.com/mikefarah/yq) -- do use the right tool with the link provided.


### The OpenShift Cluster

Since we're deploying Instana on OpenShift, an OpenShift cluster is required.

It doesn't really matter whether it's a self-managed or managed cluster, like RedHat OpenShift Kubernetes Service (ROKS) on IBM Cloud, it should just work.

Please note that the CSI-compliant storage is very important while deploying Instana on Kubernetes.

Basically we need two types of storage:
- Block storage for almost everything of the datastore components;
- `ReadWriteMany` supported file storage for raw spans, which can be set by `DATASTORE_STORAGE_CLASS_SPANS`, in a real-world multi-node cluster!


## The TL'DR Guide

You may run it in your laptop (e.g. MacBook), or a Linux machine, either way should just work as long as you can access the OpenShift cluster and the required tools are installed.

**And, make sure you've already logged into OpenShift with ClusterAdmin permission.**


### 0. Prepare

Typically, when setting up OpenShift, you've decided the way how to expose the services. Here I'd assume we're going to use the default route to expose Instana services.

```sh
# Clone the repo
git clone https://github.com/brightzheng100/instana-server-on-k8s.git
cd instana-server-on-k8s/all-in-openshift

# Make a directory for hosting some working files, which will be ignored by Git
mkdir _wip

# Export required environment variables
export INSTANA_EXPOSED_FQDN="instana.`oc get ingresses.config/cluster -o=jsonpath='{.spec.domain}'`"    # or your desired FQDN
export INSTANA_AGENT_KEY="<THE LICENSE'S AGENT KEY>"
export INSTANA_DOWNLOAD_KEY="<THE LICENSE'S DOWNLOAD KEY>"
export INSTANA_SALES_KEY="<THE LICENSE'S SALES KEY>"
```

And, quite importantly, you have to take care of the StorageClasses for a list of persistence components.
- For normal datastore components, like `DATASTORE_STORAGE_CLASS_CASSANDRA`, use block storage;
- For `DATASTORE_STORAGE_CLASS_SPANS`, you must set the StorageClass that supports `ReadWriteMany`, or S3 compatible storage, in a real-world multi-node cluster!

So get ready and export them accordingly to fit into your Kubernetes context.

In my case, I use `ocs-storagecluster-cephfs` as the file-based storage for `DATASTORE_STORAGE_CLASS_SPANS`, while `ocs-storagecluster-ceph-rbd` for the rest, both are available in OCS/Ceph.

You may have a check on what storage classes should be used, by running: `kubectl get storageclass`.

```sh
export DATASTORE_STORAGE_CLASS_BEEINSTANA="ocs-storagecluster-ceph-rbd"
export DATASTORE_SIZE_BEEINSTANA="10Gi"

export DATASTORE_STORAGE_CLASS_CASSANDRA="ocs-storagecluster-ceph-rbd"
export DATASTORE_SIZE_CASSANDRA="10Gi"

export DATASTORE_STORAGE_CLASS_CLICKHOUSE="ocs-storagecluster-ceph-rbd"
export DATASTORE_SIZE_CLICKHOUSE_DATA="10Gi"
export DATASTORE_SIZE_CLICKHOUSE_LOG="1Gi"

export DATASTORE_STORAGE_CLASS_ZOOKEEPER="ocs-storagecluster-ceph-rbd"
export DATASTORE_SIZE_ZOOKEEPER="10Gi"

export DATASTORE_STORAGE_CLASS_ELASTICSEARCH="ocs-storagecluster-ceph-rbd"
export DATASTORE_SIZE_ELASTICSEARCH="10Gi"

export DATASTORE_STORAGE_CLASS_KAFKA="ocs-storagecluster-ceph-rbd"
export DATASTORE_SIZE_KAFKA="2Gi"
export DATASTORE_STORAGE_CLASS_KAFKA_ZK="ocs-storagecluster-ceph-rbd"
export DATASTORE_SIZE_KAFKA_ZK="10Gi"

export DATASTORE_STORAGE_CLASS_POSTGRES="ocs-storagecluster-ceph-rbd"
export DATASTORE_SIZE_POSTGRES="3Gi"

export DATASTORE_STORAGE_CLASS_SYNTHETICS="ocs-storagecluster-ceph-rbd"
export DATASTORE_SIZE_SYNTHETICS="5Gi"

export DATASTORE_STORAGE_CLASS_SPANS="ocs-storagecluster-cephfs"
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

  To use another desired version of Instana, if available, do something like this:

  ```sh
  export INSTANA_OPERATOR_VERSION="261.2.0"
  export INSTANA_OPERATOR_IMAGETAG="261-2"
  ```

  > Note: configured version of Instana may or may not work with currently configured datastore components.

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

  installing-scc

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
  # check before proceeding: wait 20 mins for expected 21 more pods
  # Note: this depends on the beta features as well so don't be that exact
  check-namespaced-pod-status-and-keep-displaying-info "instana-core" 20 21 "kubectl get pod -n instana-core"

  installing-instana-server-unit
  # check before proceeding: wait 10 mins for expected 6 pods
  check-namespaced-pod-status-and-keep-displaying-info "instana-units" 10 6 "kubectl get pod -n instana-units"

  exposing-instana-server-services
  ```

</details>


Please note that multitenancy is fully supported when Instana is deployed on Kubernetes / OpenShift, as long as we have sufficient resources / worker nodes. What we need to do is to deploy multiple `Unit` objects, say `tenant-dev` and `tenant-prod`, like what we did for `tenant0-unit0`.


### 3. How to access?

Once you've gone through all above steps successfully, the Instana should have been deployed.

Now, you can print out the access info:

```sh
how-to-access-instana
```

Important note: if the Chrome blocks the URL due to self-signed cert, you may refer to [this Gist](https://gist.github.com/brightzheng100/d124ff73e39c68a66fdc97a0a7d04b11) for the access.
