# Instana Server on single-node K8s

This repository guides you through how to set up Instana within a single-VM on Kubernetes, bootstrapped by `kubeadm`, from scratch.

The architecture can be illustrated as below:

![Architecture of Instana Server](./misc/architecture.png)

## Prerequisites

### The VM specs

The VM should meet these minimum specs:
- 16 vCPU
- 64G RAM
- 500G HD (SSD preferred)

Tested Operating Systems, on `amd64` / `x86_64` arch:
- RHEL 8.x

> Note: the total of default memory requests exceeds **64G** so I've scaled down some components to fit into above specs. Refer to [`manifests/datastores-cr.yaml`](./manifests/datastores-cr.yaml) and [`manifests/core.yaml`](./manifests/core.yaml) for the details.

The resource utilization can be referred to below output -- so the RAM with 64G is at risk:

```sh
$ kubectl describe no/itzvsi-550004ghs4-dv3hyjx3
...
  Resource           Requests       Limits
  --------           --------       ------
  cpu                11700m (73%)   14 (87%)
  memory             59220Mi (92%)  75535Mi (117%)
...
```


### Tools

A series tools will be installed automatically, which include:
- `kubelet`, with configurable version
- `kubeadm`, with configurable version
- `kubectl`, with configurable version
- `cri-o`, with configurable version
- `kubectl-instana plugin`, with configurable version
- [`yq`](https://github.com/mikefarah/yq)

And, there are some other tools required, which typically will be there already but the `0-init.sh` will have a double-check.
So please install them accordingly beforehand.
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
export INSTANA_EXPOSED_FQDN="<THE FQDN, e.g. 159.23.100.15.nip.io or mydomain.com>"
export INSTANA_AGENT_KEY="<THE LICENSE'S AGENT KEY>"
export INSTANA_DOWNLOAD_KEY="<THE LICENSE'S DOWNLOAD KEY>"
export INSTANA_SALES_KEY="<THE LICENSE'S SALES KEY>"
```

Optionally, you may export more environment variables to influence the installation if that makes sense -- the process will respect the desired changes you want to make.

Please refer to [`scripts/13-init-vars.sh`](./scripts/13-init-vars.sh) for the potential environment variables that can be exported.

For example, to change the default Instana console login password, do something like this:

```sh
export INSTANA_ADMIN_PWD=MyCoolPassword
```

Or, to use another desired version of Instana, if available, do something like this:

```sh
export INSTANA_VERSION=243-5
```

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
So, run below commands, well, custom functions actually, one by one instead:

```sh
installing-k8s-tools
installing-k8s-cri

bootstrapping-k8s
progress-bar 1

getting-ready-k8s
installing-k8s-cni
```

### 3. Install Instana

Similarly, if you want to install Instana in one shot, do this:

```sh
./3-install-instana.sh
```

But, I'd highly recommend you do it step by step so you have better chance to troubleshoot.
So, run below commands, well, custom functions actually, one by one instead:

```sh
installing-tools
creating-namespaces
installing-local-path-provisioner

installing-cert-manager
# check before proceeding: wait 5 mins for expected 3 pods
check-namespaced-pod-status-and-keep-displaying-info "cert-manager" 5 3 "kubectl get pod -n cert-manager"

installing-instana-operator

installing-instana-datastores
# check before proceeding: wait 10 mins for expected 8 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-datastores" 10 8 "kubectl get pod -n instana-datastores"

installing-instana-server-components-secret-image-pullsecret
installing-instana-server-components-secret-instana-core
installing-instana-server-components-secret-instana-tls
installing-instana-server-components-secret-tenant0-unit0

installing-instana-server-components-core
# check before proceeding: wait 10 mins for expected 20 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-core" 10 20 "kubectl get pod -n instana-core"

installing-instana-server-components-unit
# check before proceeding: wait 10 mins for expected 6 pods
check-namespaced-pod-status-and-keep-displaying-info "instana-units" 10 6 "kubectl get pod -n instana-units"

exposing-instana-server-servies
```

### 4. How to access?

Once you've gone through all above steps successfully, the Instana should have been deployed.
Now, you can print out the access info:

```sh
how-to-access-instana
```

## The step-by-step guide

If you're curious enough, check out the [detailed guide](./README-DETAILED.md) for the steps.
