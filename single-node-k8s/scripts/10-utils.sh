#!/bin/bash

color_green="\x1b[32m"
color_red="\x1b[31m"
color_yellow="\x1b[33m"
color_end="\x1b[m"

SLEEP_DURATION=1

#
# Logging
#
# Usage: 
#   logme "<COLOR CODE>" "<Message>"
# For example:
#   logme "$color_green" "done"
#
function logme {
  printf "  $1 $2 ${color_end}\n"
}

#
# Check whether a tool is installed
#
# Usage: 
#   is_required_tool_missed "<TOOL'S NAME>"
# For example:
#   is_required_tool_missed "openssl"
#
function is_required_tool_missed {
    echo "Checking required tool: $1 ... "
    if [ -x "$(command -v $1)" ]; then
        logme "$color_green" "installed"
        false
    else
        logme "$color_red" "NOT installed"
        true
    fi
}

#
# export $1 with given default value of $2, if $1 doesn't exist or set
# Usage:
#   export_var_with_default <VAR NAME> <VAR'S DEFAULT VALUE> [<1 to FORCE TO SET WITH DEFAULT VALUE>]
#   where
#     $1 - the var name
#     $2 - the var default value
#     $3 - optional, "1" to force set with default value
# Example:
#   export_var_with_default "MY_VAR" "DEFAULT_VALUE"
#
function export_var_with_default() {
  var_name=$1
  var_default_value=$2
  var_force_set=$3

  #echo "params: $var_name, $var_default_value, $var_force_set"
  var_current_value=""
  eval var_current_value='$'"$var_name"

  #echo "before: $var_name = $var_current_value"

  # if $1 doesn't exist or set
  if [[ "x${var_current_value}" == "x" || "${var_force_set}" == "1" ]]; then
    var_current_value="$var_default_value"
  fi
  export $var_name="$var_current_value"
  #echo "after: $var_name = ${var_current_value}"
}

#
# return with RED warning message if var from $1 is not exported
# Usage:
#   quit_when_var_not_set <VAR NAME>
# Example:
#   quit_when_var_not_set "INSTANA_SALES_KEY"
#
function quit_when_var_not_set() {
  #echo "var: $1"
  eval var_value='$'"$1"

  if [[ -z "$var_value" ]]; then 
    logme "$color_red"  "You must explictly export this variable: $1"
    return 0;
  fi
}

#
# Diplay a progress bar while waiting things, which looks like:
# ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇| 100% - waiting for 2 mins
# Usage:
#   progress-bar <TIME IN MINUTES>
# Example:
#   progress-bar 1
#
function progress-bar {
  local duration
  local columns
  local space_available
  local fit_to_screen  
  local space_reserved

  space_reserved=30                     # reserved width for the message like: | 100% - waiting for 20 mins
  duration=${1}                         # by mins
  duration=$(( duration*60 ));          # convert it to seconds
  if [[ "$__DEBUG__" == "true" ]]; then # this is for debug mode only to accelerate things
    duration=10; 
  fi  
  columns=$(tput cols)
  space_available=$(( columns-space_reserved ))

  if (( duration < space_available )); then 
  	fit_to_screen=1; 
  else 
    fit_to_screen=$(( duration / space_available ));
    fit_to_screen=$((fit_to_screen+1)); 
  fi

  already_done() { for ((done=0; done<(elapsed / fit_to_screen) ; done=done+1 )); do printf "▇"; done }
  remaining() { for (( remain=(elapsed/fit_to_screen) ; remain<(duration/fit_to_screen) ; remain=remain+1 )); do printf " "; done }
  percentage() { printf "| %s%% - waiting for %s mins" $(( ((elapsed)*100)/(duration)*100/100 )) $(( (duration)/60 )); }
  clean_line() { printf "\r"; }

  for (( elapsed=1; elapsed<=duration; elapsed=elapsed+1 )); do
      already_done; remaining; percentage
      sleep "$SLEEP_DURATION"
      clean_line
  done
  clean_line
  printf "\n";
}

# 
# Sleep until all specified namespace's pods are running/completed.
#
# Usage:
#   check-namespaced-pod-status "<NAMESPACE>" <TIMEOUT IN MIN> <MIN PODS READY, Optional and defaut 1>
# For example:
# - To check "instana-datastores" namespace and expect at least 3 pods, with 5mins timeout
#   check-namespaced-pod-status "instana-datastores" 5 3
#
function check-namespaced-pod-status {
    local namespace="$1"
    local timeout_min=$2
    local expected_pods_min="${3:-1}"           # optional, defaults to 1

    local wc_all=0
    local wc_remaining=0

    logme "$color_yellow" "--------------------------"

    finished=false
    for ((time=1;time<$timeout_min;time++)); do
        wc_all="`kubectl get pod --no-headers=true -n $namespace | grep 'Running\|Completed' | wc -l  | xargs`"
        wc_remaining="`kubectl get pod --no-headers=true -n $namespace | grep -v 'Running\|Completed' | wc -l | xargs`"
        
        logme "$color_yellow" "Waiting for pods in \"$namespace\" to be ready: expected >= $expected_pods_min; current = $wc_all; ongoing = $wc_remaining... recheck in $time of $timeout_min mins"
        
        if [ $wc_remaining -le 0 ] && [ $wc_all -ge $expected_pods_min ]; then
            # no more remaining
            finished=true
            logme "$color_green" "DONE!"
            break
        else
            echo ""
            kubectl get pod -n $namespace | grep -v 'Running\|Completed'
        fi

        # wait 1 min
        progress-bar 1
    done

    if [[ "$finished" == "false" ]]; then
        logme "$color_red" "Hmm, timeout after retrying in $timeout_min mins!"
        exit 99
    fi
}

# 
# Keep checking whether all specified namespace's pods are running/completed,
# while displaying some log lines by a specific command
#
# Usage:
#   check-namespaced-pod-status-and-keep-displaying-logs-lines
#     $1 - namespace
#     $2 - timeout in minute
#     $3 - minimum num of expected pods
#     $4 - the command to run for scaping the logs / info
#
# Example:
#   Check and wait "pods" ready and keep displaying the pods' status, with 5 mins timeout window
#     check-namespaced-pod-status-and-keep-displaying-info "cert-manager" 5 3 "kubectl get pod -n cert-manager"
#
function check-namespaced-pod-status-and-keep-displaying-info {
    local namespace="$1"
    local timeout_min=$2
    local expected_pods_min="$3"
    local display_command="$4"

    local wc_all=0
    local wc_remaining=0

    logme "$color_yellow" "--------------------------"

    finished=false
    for ((time=1;time<$timeout_min;time++)); do
        wc_all="`kubectl get pod --no-headers=true -n $namespace | grep 'Running\|Completed' | wc -l  | xargs`"
        wc_remaining="`kubectl get pod --no-headers=true -n $namespace | grep -v 'Running\|Completed' | wc -l | xargs`"

        # display logs
        eval "$display_command"
        
        logme "$color_yellow" "Waiting for pods in \"$namespace\" to be running/completed: expected >= $expected_pods_min; current = $wc_all; ongoing = $wc_remaining... recheck in $time of $timeout_min mins"
        
        if [ $wc_remaining -le 0 ] && [ $wc_all -ge $expected_pods_min ]; then
            # no more remaining, or just a few ignorable pods
            finished=true
            logme "$color_green" "DONE!"
            break
        else
            echo ""
            kubectl get pod -n $namespace | grep -v 'Running\|Completed'
        fi

        # wait 1 min
        progress-bar 1
    done

    if [[ "$finished" == "false" ]]; then
        logme "$color_red" "Hmm, timeout after retrying in $timeout_min mins!"
        exit 99
    fi
}

#
# Note: in cloud env, the default route of OpenShift might exceed the CN limit of 64 chars
# like: instana.itzroks-550004ghs4-0sskrs-6ccd7f378ae819553d37d5f2ee142bd6-0000.eu-gb.containers.appdomain.cloud
# so we need to truncate a bit to make it work
# Usage:
#   get-signing-fqdn "<CONFIGURED FQDN>"
# Example: 
#   get-signing-fqdn instana.itzroks-550004ghs4-0sskrs-6ccd7f378ae819553d37d5f2ee142bd6-0000.eu-gb.containers.appdomain.cloud
#   - return: *.eu-gb.containers.appdomain.cloud
function get-signing-fqdn {
    local configured_fqdn="$1"
    local fqdn_section=""

    declare -a array
    array=($(echo $configured_fqdn | tr "." "\n"))
    length=${#array[@]}
    local e=""

    ## truncate accordingly if configured fqdn > 62 (+ *.) so >=64
    if [ ${#configured_fqdn} -gt 62 ]; then
        for (( i=${length}; i>1; i-- )); do
            e="${array[$i]}"
            tl=$(( ${#fqdn_section} + ${#e} ));
            if [ ${tl} -le 62 ]; then
                fqdn_section=".${e}${fqdn_section}"
            fi
        done
    else
        fqdn_section=".${configured_fqdn}"
    fi

    echo "*${fqdn_section}"
}
