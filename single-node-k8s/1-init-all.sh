#!/bin/bash

source ./scripts/10-utils.sh
#logme "$color_green" "source ./scripts/10-utils.sh"

source /etc/os-release
case $ID in
  rhel) 
    # RHEL
    #logme "$color_green" "RHEL OS detected"
    #logme "$color_green" "source ./scripts/11-init-k8s-rhel.sh"
    source ./scripts/11-init-k8s-rhel.sh
    ;;
  centos) 
    # CentOS
    #logme "$color_green" "CentOS OS detected, which SHOUD work but haven't fully tested."
    #logme "$color_green" "source ./scripts/11-init-k8s-rhel.sh"
    source ./scripts/11-init-k8s-rhel.sh
    ;;
  ubuntu) 
    # Ubuntu
    logme "$color_green" "RHEL OS detected"
    source ./scripts/11-init-k8s-rhel.sh
    source ./scripts/11-init-k8s-ubuntu.sh
    ;;
  *) 
    # Others
    logme "$color_red" "!!! Unsupported OS detected: $ID !!!"
    return 0
    ;;
esac

#logme "$color_green" "source ./scripts/12-init-instana.sh"
source ./scripts/12-init-instana.sh

if [[ "$INIT_STATUS" != "DONE" ]]; then
    #logme "$color_green" "source ./scripts/13-init-vars.sh"
    source ./scripts/13-init-vars.sh
fi
