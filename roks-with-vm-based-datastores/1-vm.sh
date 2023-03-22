#!/bin/bash

### Installing Docker
function installing-docker {
  echo "----> installing-docker"
  
  # Remove potential lagecy components, if any
  sudo dnf remove -y \
  docker \
  docker-client \
  docker-client-latest \
  docker-common \
  docker-latest \
  docker-latest-logrotate \
  docker-logrotate \
  docker-engine \
  podman \
  runc

  # Add Docker repo
  # As Docker CE is not officially supported on RHEL 8, we use CentOs repo here
  sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

  # Now install Docker components
  sudo dnf install -y docker-ce docker-ce-cli containerd.io

  # Start Docker daemon
  sudo systemctl start docker

  # Have a try and we should be able to see "Hello from Docker!"
  sudo docker run hello-world

  # Finally add our current user into "docker" group to avoid "sudo" while running docker CLI
  # Re-login to the VM to take effect
  sudo usermod -aG docker $USER
}

### Installing Instana CLI
function installing-instana-cli {
  echo "----> installing-instana-cli"

  sudo dnf update -y

  cat <<EOF | sudo tee /etc/yum.repos.d/Instana-Product.repo
[instana-product]
name=Instana-Product
baseurl=https://self-hosted.instana.io/rpm/release/product/rpm/generic/x86_64/Packages
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://self-hosted.instana.io/signing_key.gpg
priority=5
sslverify=1
#proxy=http://x.x.x.x:8080
#proxy_username=
#proxy_password=
EOF

  sudo dnf makecache -y
  sudo dnf install -y instana-console-${1}

  instana version

  sudo dnf install python3-dnf-plugin-versionlock -y
  sudo dnf versionlock add instana-console
}

### Installing Instana Components
# ${1} - exposed host/ip for Instana Server components
# ${2} - Instana's agent key
function installing-instana-components {
  echo "----> installing-instana-components"

  # Prepare the settings file
  INSTANA_DATASTORE_HOST=${1} && \
  INSTANA_AGENT_KEY=${2} && \
  cat <<EOF | sudo tee _wip/db-settings.hcl
type        = "single-db"
host_name   = "${INSTANA_DATASTORE_HOST}"

dir {
  metrics   = "/mnt/metrics"     // data dir for metrics
  traces    = "/mnt/traces"      // data dir for traces
  data      = "/mnt/data"        // data dir for any other data
  logs      = "/var/log/instana" // log dir
}

docker_repository {
  base_url = "containers.instana.io"
  username = "_"
  password = "${INSTANA_AGENT_KEY}"
}
EOF

  # Init and install the Instana datastore components
  sudo instana datastores init -f _wip/db-settings.hcl
}

############################################################

if [ -z "${INSTANA_DATASTORE_HOST}" ] | [ -z "${INSTANA_AGENT_KEY}" ]; then 
  echo "ERROR: You must export ALL required variables prior to run the command. For example"
  echo "==========================================================="
  echo "export INSTANA_DATASTORE_HOST=\"168.1.53.253\""
  echo "export INSTANA_AGENT_KEY=\"xxxxxxxxxxxxxxx\""
  echo "export INSTANA_VERSION=\"235-1\""
  return 1;
fi

## Echo overview
echo "==========================================================="
echo "----> INSTANA_DATASTORE_HOST=${INSTANA_DATASTORE_HOST}"
echo "----> INSTANA_AGENT_KEY=${INSTANA_AGENT_KEY}"
echo "----> INSTANA_VERSION=${INSTANA_VERSION}"

## Let's orchestrate the process here
installing-docker
installing-instana-cli "${INSTANA_VERSION}"
installing-instana-components "${INSTANA_DATASTORE_HOST}" "${INSTANA_AGENT_KEY}"
echo "----> DONE! If no errors occured, you may proceed to part 2 now."
