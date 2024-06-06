#!/bin/bash

### Installing K8s tools
function installing-k8s-tools {
  logme "$color_green" "----> installing-k8s-tools"

  # Add K8s repo
  cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

  # Set SELinux in permissive mode (effectively disabling it)
  sudo setenforce 0
  sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

  # Check the available candidates by:
  #  sudo dnf --showduplicates list kubelet
  #  sudo dnf --showduplicates list kubeadm
  #  sudo dnf --showduplicates list kubectl
  sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

  # Enable kubelet
  sudo systemctl enable --now kubelet
  
  logme "$color_green" "DONE"
}

### Installing K8s CRI with CRI-O
function installing-k8s-cri {
  logme "$color_green" "----> installing-k8s-cri"

  PROJECT_PATH=prerelease:/main
  cat <<EOF | sudo tee /etc/yum.repos.d/cri-o.repo
[cri-o]
name=CRI-O
baseurl=https://pkgs.k8s.io/addons:/cri-o:/$PROJECT_PATH/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/addons:/cri-o:/$PROJECT_PATH/rpm/repodata/repomd.xml.key
EOF
  sudo dnf install cri-o -y

  # Enable and start cri-o service
  sudo systemctl enable crio
  sudo systemctl start crio
  
  logme "$color_green" "DONE"
}

### Bootstrapping K8s
function bootstrapping-k8s {
  logme "$color_green" "----> bootstrapping-k8s"

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

  # 4. Bootstrap it
  # Note: we customize the service-node-port-range: 443-32767
  # To change existing cluster, `vi /etc/kubernetes/manifests/kube-apiserver.yaml`,
  # add `--service-node-port-range=80-32767`, save then `sudo systemctl restart kubelet`
  #sudo kubeadm init --pod-network-cidr=192.168.0.0/16
  sudo kubeadm init --config manifests/kubeadm-init-conf.yaml
  
  logme "$color_green" "DONE"
}

### Getting ready with K8s
function getting-ready-k8s {
  logme "$color_green" "----> getting-ready-k8s"

  # Copy over the kube config for admin access
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  # Remove the taint as we have only one node
  kubectl taint nodes --all node-role.kubernetes.io/control-plane-
  
  logme "$color_green" "DONE"
}

### Installing K8s CNI with Calico
function installing-k8s-cni {
  logme "$color_green" "----> installing-k8s-cni"

  kubectl apply -f "${CALICO_MANIFEST_FILE}"
  
  logme "$color_green" "DONE"
}

### Installing local-path-provisioner
function installing-local-path-provisioner {
  logme "$color_green" "----> installing-local-path-provisioner"

  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.27/deploy/local-path-storage.yaml

  cat manifests/local-path-config.yaml | envsubst '$DATASTORE_MOUNT_ROOT' | kubectl apply -f -

  logme "$color_green" "DONE"
}

### Installing Instana tools: Kubectl plugin, yq, helm
function installing-tools {
  logme "$color_green" "----> installing-tools"

  # Note: now we use Helm Chart, not plugin, to install operator
  # Instana kubectl plugin
#   logme "$color_green" "Instana kubectl plugin..."
#   cat << EOF | sudo tee /etc/yum.repos.d/instana.repo
# [instana-product]
# name=Instana-Product
# baseurl=https://_:${INSTANA_DOWNLOAD_KEY}@artifact-public.instana.io/artifactory/rel-rpm-public-virtual/
# enabled=1
# gpgcheck=0
# gpgkey=https://_:${INSTANA_DOWNLOAD_KEY}@artifact-public.instana.io/artifactory/api/security/keypair/public/repositories/rel-rpm-public-virtual
# repo_gpgcheck=1
# EOF
#   sudo dnf makecache -y
#   #sudo dnf --showduplicates list instana-kubectl
#   sudo dnf install -y instana-kubectl-${INSTANA_VERSION}
#   sudo dnf install python3-dnf-plugin-versionlock -y
#   sudo dnf versionlock add instana-console-${INSTANA_VERSION}
#   logme "$color_green" "`kubectl instana --version`"

#   logme "$color_green" "Instana kubectl plugin - DONE"

  # yq
  logme "$color_green" "yq..."
  curl -sSL --output _wip/yq_linux_amd64 https://github.com/mikefarah/yq/releases/download/v4.31.2/yq_linux_amd64
  chmod +x _wip/yq_linux_amd64
  sudo mv _wip/yq_linux_amd64 /usr/local/bin/yq
  
  logme "$color_green" "yq - DONE"

  # helm
  curl -fsSL -o _wip/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 _wip/get_helm.sh
  ./_wip/get_helm.sh

  # jq
  #sudo dnf install jq -y
}
