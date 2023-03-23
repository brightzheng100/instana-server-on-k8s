#!/bin/bash

source ../single-node-k8s/scripts/10-utils.sh

source ../single-node-k8s/scripts/12-init-instana.sh
source ./scripts/12-init-instana.sh

if [[ "$INIT_STATUS" != "DONE" ]]; then
    source ./scripts/13-init-vars.sh
fi
