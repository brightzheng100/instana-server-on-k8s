# Instana Server on single-node K8s

This repository guides you through how to set up Instana within a single-VM on Kubernetes, bootstrapped by `kubeadm`, from scratch.

Latest review on 09 Jan 2024, with:

- OS on `amd64` / `x86_64` CPU arch:
  - RHEL 8.x (**Re-tested**)
  - Ubuntu 20.04 (**To be re-tested**)
- on Kubernetes version `1.28`, which is configurable through `export K8S_VERSION=<YOUR DESIRED VERSION, e.g. 1.28>`
- on Instana version `261-2`, which is configurable through `export INSTANA_OPERATOR_VERSION=<YOUR DESIRED VERSION, e.g. 261.2.0>; export INSTANA_OPERATOR_IMAGETAG=<YOUR DESIRED VERSION, e.g. 261-2>`

Please note that there are quite some configurable features in Instana. Due to resource limitation of my testing VM, by default I only turn on `BeeInstana` among below items:
- BeeInstana
- Logging (beta)
- Automation / Action Framework (beta)
- Synthetic Monitoring (beta)
- ...

You may turn on more if you want, by updating [`core.yaml`](./manifests/core.yaml)'s **featureFlags**.

For the complete configurable features, please refer to official doc [here](https://www.ibm.com/docs/en/instana-observability/current?topic=openshift-enabling-optional-features).


## Architecture

The architecture can be illustrated as below:

![Architecture of Instana Server](./misc/architecture.png)


## Prerequisites

### The VM specs

The VM should meet these minimum specs:
- 16 vCPU
- 64G RAM
- 500G HD (SSD preferred). If the disk is additional one, please mount it to `/storage`, or configure it by `export DATASTORE_MOUNT_ROOT=<YOUR_DESIRED_MOUNT_POINT>`

Please note that the total of default memory requests exceed **64G** so I've scaled down some components to fit into above specs.
Refer to `manifests/datastore-*.yaml` and [`manifests/core.yaml`](./manifests/core.yaml) for the details.

The current setup's resource utilization can be referred to below output -- so the RAM with 64G is at risk as it's overcommitted to be 141%:

```sh
$ kubectl describe node/itzvsi-550004ghs4-dv3hyjx3
...
Allocated resources:
  Resource           Requests          Limits
  --------           --------          ------
  cpu                13550m (84%)      8 (50%)
  memory             61744164Ki (93%)  88528968Ki (134%)
```


### Tools

A series of tools will be installed automatically, which include:
- `kubelet`, with configurable version
- `kubeadm`, with configurable version
- `kubectl`, with configurable version
- `cri-o`, with configurable version
- [`yq`](https://github.com/mikefarah/yq)

And, there are some other tools required, which typically have been installed already in the VM.

Anyway, the init process will have a double-check so please make sure they're installed beforehand.
- `curl`
- `openssl`


## The TL'DR guide

Go through below steps within the to-be-server VM.

### 0. Prepare

```sh
# Clone the repo
git clone https://github.com/brightzheng100/instana-server-on-k8s.git
cd instana-server-on-k8s/single-node-k8s

# Make a directory for hosting some working files, which will be ignored by Git
mkdir _wip

# Export required environment variables
export INSTANA_EXPOSED_FQDN="<THE FQDN, e.g. 20.26.139.84.nip.io>"
export INSTANA_AGENT_KEY="<THE LICENSE'S AGENT KEY>"
export INSTANA_DOWNLOAD_KEY="<THE LICENSE'S DOWNLOAD KEY>"
export INSTANA_SALES_KEY="<THE LICENSE'S SALES KEY>"
```

Optionally, you may export more environment variables to influence the installation if that makes sense -- the process will respect the desired changes you want to make.

Please refer to [`scripts/13-init-vars.sh`](./scripts/13-init-vars.sh) for the potential environment variables that can be configured.

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

Now, the preparation is done, and let's get started!


### 1. Init it

```sh
source 1-init-all.sh
```


### 2. Spin up K8s

If you want to spin up K8s in one shot, do this:

```sh
./2-install-k8s.sh
```

But, I'd highly recommend you do it step by step so you have better chance to troubleshoot.
So, run below commands, well, custom functions actually, one by one instead.

<details>
  <summary>Click here to show the step-by-step commands.</summary>
  
  ```sh
  installing-k8s-tools
  installing-k8s-cri

  bootstrapping-k8s
  progress-bar 1

  getting-ready-k8s

  installing-k8s-cni

  installing-local-path-provisioner

  installing-tools
  ```
</details>


### 3. Install Instana

Similarly, if you want to install Instana in one shot, do this:

```sh
./3-install-instana.sh
```

But, I'd highly recommend you do it step by step so you have better chance to troubleshoot.
So, run below commands, well, custom functions actually, one by one instead.


<details>
  <summary>Click here to show the step-by-step commands.</summary>
  
  ```sh
  creating-namespaces
  installing-local-path-provisioner

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


### 4. How to access?

Once you've gone through all above steps successfully, the Instana should have been deployed.
Now, you can print out the access info:

```sh
how-to-access-instana
```

## The Scripts & YAML files

If you really want do dive deeper into the details, please check out the scripts and YAML files accordingly.
