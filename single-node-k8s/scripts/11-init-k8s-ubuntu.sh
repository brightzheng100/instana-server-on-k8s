#!/bin/bash

#source 11-init-k8s-rhel.sh

### Installing K8s tools
function installing-k8s-tools {
  logme "$color_green" "----> installing-k8s-tools"

  sudo apt-get install -y ca-certificates curl gpg

  sudo mkdir -p /etc/apt/keyrings

  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

  sudo apt-get update

  # Check the available candidates by:
  #  sudo apt-cache madison kubelet
  #  sudo apt-cache madison kubeadm
  #  sudo apt-cache madison kubectl
  sudo apt-get install -y kubelet kubeadm kubectl
  sudo apt-mark hold kubelet kubeadm kubectl

  # Enable kubelet
  sudo systemctl enable kubelet
  
  logme "$color_green" "DONE"
}

### Installing K8s CRI with CRI-O
function installing-k8s-cri {
  logme "$color_green" "----> installing-k8s-cri"

  # As per the official doc (https://cri-o.io/), there are different path for different Ubuntu version, sigh!
  OS="Debian_Unstable"
  if [[ $(lsb_release -rs) == "18.04" ]]; then
    OS="xUbuntu_18.04"
  elif [[ $(lsb_release -rs) == "19.04" ]]; then
    OS="xUbuntu_19.04"
  elif [[ $(lsb_release -rs) == "19.10" ]]; then
    OS="xUbuntu_19.10"
  elif [[ $(lsb_release -rs) == "20.04" ]]; then
    OS="xUbuntu_20.04"
  elif [[ $(lsb_release -rs) == "21.04" ]]; then
    OS="xUbuntu_21.04"
  elif [[ $(lsb_release -rs) == "21.10" ]]; then
    OS="xUbuntu_21.10"
  elif [[ $(lsb_release -rs) == "22.04" ]]; then
    OS="xUbuntu_22.04"
  fi

  sudo mkdir -p /usr/share/keyrings
  curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | \
    sudo gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
  curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/Release.key | \
    sudo gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" | \
    sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
  echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" | \
    sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list

  sudo apt-get update
  sudo apt-get install cri-o cri-o-runc -y

  # Enable and start cri-o service
  sudo systemctl enable crio
  sudo systemctl start crio
  
  logme "$color_green" "DONE"
}

### Bootstrapping K8s

### Getting ready with K8s

### Installing K8s CNI with Calico

### Installing Instana tools: Kubectl plugin, yq, helm
function installing-tools {
  logme "$color_green" "----> installing-tools"

  # Note: now we use Helm Chart, not plugin, to install operator
#   # Instana kubectl plugin
#   logme "$color_green" "Instana kubectl plugin..."
#   echo 'deb [signed-by=/usr/share/keyrings/instana-archive-keyring.gpg] https://artifact-public.instana.io/artifactory/rel-debian-public-virtual generic main' \
#     | sudo tee /etc/apt/sources.list.d/instana-product.list

#   cat << EOF | sudo tee /etc/apt/auth.conf
# machine artifact-public.instana.io
#   login _
#   password ${INSTANA_AGENT_KEY}
# EOF

#   sudo apt-get update -y
#   # Check the available candidates by:
#   #  sudo apt-cache madison instana-kubectl
#   sudo apt-get install -y instana-kubectl=${INSTANA_VERSION}

#   cat << EOF | sudo tee /etc/apt/preferences.d/instana-kubectl
# Package: instana-kubectl
# Pin: version ${INSTANA_VERSION}
# Pin-Priority: 1000
# EOF

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