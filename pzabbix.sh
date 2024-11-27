#!/bin/bash

# General script constants
FULL_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
CURRDIR="$(dirname "$FULL_SCRIPT_PATH")"
SCRIPT_NAME="$(basename "$FULL_SCRIPT_PATH")"

# Version control constants
REPO_OWNER="phonevox"
REPO_NAME="pzabbix"
REPO_URL="https://github.com/$REPO_OWNER/$REPO_NAME"
ZIP_URL="$REPO_URL/archive/refs/heads/main.zip"
APP_VERSION="v0.1.0"

source $CURRDIR/lib/useful.sh
source $CURRDIR/lib/easyflags.sh
source $CURRDIR/lib/versioncontrol.sh

# Additional information
SYSTEM_OS=$(get_os)

# === FLAGS BELOW ===

# General flags
add_flag "d" "dry" "Do NOT make changes to the system" bool
add_flag "t" "test" "Test mode" bool
add_flag "v" "verbose" "Verbose mode" bool
# add_flag "brk" "break" "Break mode (ignore restrictions)" bool  # TODO(adrian): implement this later

# Zabbix configuration flags
add_flag "sa" "server-active" "Zabbix: ServerActive" ip/domain
add_flag "s" "server" "Zabbix: Server" ip/domain
add_flag "S" "S" "Zabbix: ServerActive and Server" ip/domain
add_flag "H" "hostname" "Zabbix: Hostname" string
add_flag "mtdt" "metadata" "Zabbix: HostMetadata, maximum of 255 characters" string

# quick server location
add_flag "ovh:HIDDEN" "ovh" "Phonevox: Metadata OVH" bool
add_flag "qnax:HIDDEN" "qnax" "Phonevox: Metadata QNAX" bool
add_flag "local:HIDDEN" "local" "Phonevox: Metadata Local Server" bool

set_description "Zabbix installation utilitary made by Phonevox Group Technology"
parse_flags "$@"

# === FLAGS PARSED ===

# Script-related variables
ZABBIX_CONFIG_FILE_NAME="zabbix_agentd.conf"
ZABBIX_DEFAULT_PATH="/etc/zabbix"
ZABBIX_CONFIG_FILE="$ZABBIX_DEFAULT_PATH/$ZABBIX_CONFIG_FILE_NAME"

SYSTEM_OS_VERSION="7"
ZABBIX_VERSION="5.0"
ZABBIX_RPM="https://repo.zabbix.com/zabbix/$ZABBIX_VERSION/rhel/$SYSTEM_OS_VERSION/x86_64/zabbix-release-latest.el$SYSTEM_OS_VERSION.noarch.rpm"

ZABBIX_SERVER=""
ZABBIX_SERVER_ACTIVE=""
ZABBIX_HOSTNAME=""
ZABBIX_METADATA=""

# Flag-related configs
hasFlag "d" && _DRY=true || _DRY=false
hasFlag "t" && _TEST=true || _TEST=false
hasFlag "v" && _VERBOSE=true || _VERBOSE=false
hasFlag "brk" && _BREAK=true || _BREAK=false
hasFlag "s" && ZABBIX_SERVER=$(getFlag "s")
hasFlag "sa" && ZABBIX_SERVER_ACTIVE=$(getFlag "sa")
hasFlag "S" && ZABBIX_SERVER=$(getFlag "S"); ZABBIX_SERVER_ACTIVE=$ZABBIX_SERVER
hasFlag "H" && ZABBIX_HOSTNAME=$(getFlag "H")
hasFlag "mtdt" && ZABBIX_METADATA=$(getFlag "mtdt")

(
$_DRY && (echo "Dry mode is enabled.") || (echo "Dry mode is disabled.")
$_TEST && (echo "Test mode is enabled.") || (echo "Test mode is disabled.")
$_VERBOSE && (echo "Verbose mode is enabled.") || (echo "Verbose mode is disabled.")
) > /dev/null # temporarily mute this :)

# === THINGS ===

# "safe-run", abstraction to "run" function, so it can work with our dry mode
# Usage: same as run
function srun() {
    local CMD=$1
    local ACCEPTABLE_EXIT_CODES=$2

    run "$CMD >/dev/null" "$ACCEPTABLE_EXIT_CODES" "$_DRY" "$_SILENT"
}

# rpm_is_installed "<rpm_name>"
function rpm_is_installed() {
    local RES=$(rpm -qa | grep -i $1)
    if [[ "$RES" = "" ]]; then
        return 1
    else
        return 0
    fi
}

function text_in_file() {
    local text_to_search=$1
    local file_to_search=$2

    if [ -f $file_to_search ]; then
        cat $file_to_search | grep "$text_to_search" > /dev/null 2>&1
        return $?
    else
        return 1 # file does not exist
    fi
}

# if zabbix_valid_hostname "f0329kjf23"; then; fi
function zabbix_valid_hostname() {
    local hostname="$1"
    if [[ $hostname =~ ^[a-zA-Z0-9.-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

function validate_input() {
    echo "--- VALIDATING INPUT"
}

function install_agent() {
    local INSTALLED_RPM=""

    echo "--- INSTALLING ZABBIX AGENT"

    # validating current agent version
    if rpm_is_installed "zabbix.*agent-"; then
        INSTALLED_RPM=$(rpm -qa | grep -i "zabbix.*agent-")
        echo "INSTALLED RPM: $INSTALLED_RPM"

        if [[ ! "$INSTALLED_RPM" =~ ^zabbix-agent-${ZABBIX_VERSION//./\\.}.* ]]; then # not the expected zabbix version
            # clearing rpm
            $VERBOSE && echo "Clearing old zabbix rpm"
            srun "yum remove -y $INSTALLED_RPM"
        fi
    fi

    # installing the rpm (?? i dont quite understand this)
    $VERBOSE && echo "Installing zabbix-release rpm"
    srun "sudo yum --disablerepo=epel --setopt=epel.exclude=zabbix* install -y $ZABBIX_RPM"

    # installing the agent
    $VERBOSE && echo "Installing latest zabbix-agent from rpm"
    srun "sudo yum install -y zabbix-agent"

    $VERBOSE && echo "Starting zabbix-agent service"
    srun "sudo systemctl start zabbix-agent"
}

function configure_agent() {
    echo "--- EDITING ZABBIX CONFIGURATION"
    declare -A parameter_exist
    declare -A parameter_value

    # validates expected files exists
    ! [ -d $ZABBIX_DEFAULT_PATH ] && (echo "ERROR: $ZABBIX_DEFAULT_PATH does not exist" && exit 1) || (echo "ZABBIX_DEFAULT_PATH found")
    ! [ -f $ZABBIX_CONFIG_FILE ] && (echo "ERROR: $ZABBIX_CONFIG_FILE does not exist" && exit 1) || (echo "ZABBIX_CONFIG_FILE found")

    # checks if parameter exists, is duplicate, etc..
    # usage: _param_check "<zabbix_parameter>"
    _param_check() {
        local PARAMETER=$1

        _param_has_duplicate() {
            # this func adds info to associative-array 'parameter_exist'
            local PARAMETER=$1
            local QTY_MATCH_LINES=$(cat $ZABBIX_CONFIG_FILE | grep -I "^$PARAMETER=" | wc -l)

            [[ $QTY_MATCH_LINES > 1 ]] && return 0
            [[ $QTY_MATCH_LINES < 1 ]] && (parameter_exist[$PARAMETER]+=false) || (parameter_exist[$PARAMETER]+=true)
            return 1
        }

        _param_is_empty() {
            local PARAMETER=$1
            local PARAMETER_VALUE=$(cat $ZABBIX_CONFIG_FILE | grep -i "^$PARAMETER=" | awk -F"$PARAMETER=" '{print $2}')

            if [[ -z "$PARAMETER_VALUE" ]]; then return 0; fi # no value on param. return
            
            # some value on param, save and return
            parameter_value[$PARAMETER]+=$PARAMETER_VALUE
            return 1

        }

        if _param_has_duplicate "$PARAMETER"; then
            echo "ERROR: Parameter $PARAMETER is duplicated."
            exit 1
        fi

        if ! _param_is_empty "$PARAMETER"; then
            echo "INFO: Parameter $PARAMETER has value '${parameter_value[$PARAMETER]}'"
        else
            # debug tbh, doesnt really matter
            if [[ "${parameter_exist[$PARAMETER]}" == "true" ]]; then
                echo "INFO: Parameter $PARAMETER is empty"
            else
                echo "INFO: Parameter $PARAMETER is not set"
            fi
        fi
        
        return 0



    }

    # sets a value to the parameter
    # case-sensitive on parameter name
    # usage: _param_set "<zabbix_parameter>" "<value>"
    _param_set() {
        local PARAMETER=$1
        local VALUE=$2

        # _param_check "$PARAMETER"

        if [[ "${parameter_exist[$PARAMETER]}" == "true" ]]; then
            if [[ "${parameter_value[$PARAMETER]}" != "" ]]; then
                if ! [ "${parameter_value[$PARAMETER]}" = "$VALUE" ]; then
                    # unexpected value: make it right
                    sed -i "s~$PARAMETER=${parameter_value[$PARAMETER]}~$PARAMETER=$VALUE~g" $ZABBIX_CONFIG_FILE
                else
                    # expected value: do nothing
                    :
                fi
            else
                # param does not exist and have no value: make it right
                echo "sed -i \"s~$PARAMETER=~$PARAMETER=$VALUE~g\" $ZABBIX_CONFIG_FILE"
            fi
        else
            # param does not exit: add it
            echo "$PARAMETER=$VALUE" | tee -a $ZABBIX_CONFIG_FILE
        fi
    }

    # prepares the metadata content
    _metadata_create() {
        local METADATA_CONTENT=""
        _metadata_add() {
            local NEW_METADATA=$1
            METADATA_CONTENT+="$NEW_METADATA "
        }

        # here we add the metadata
        _metadata_add "$ZABBIX_METADATA"

        _metadata_add "os:linux"

        # os (linux/windows)
        # os id+version
        # asterisk version
        # special metadata from user

        if [[ ${#METADATA_CONTENT} -gt 255 ]]; then
            exit 1
        fi

        echo $METADATA_CONTENT
    }

    _param_check "Server"
    _param_check "ServerActive"
    _param_check "Hostname"
    _param_check "HostMetadata"

    _param_set "Server" "$ZABBIX_SERVER"
    _param_set "ServerActive" "$ZABBIX_SERVER_ACTIVE"
    _param_set "Hostname" "$ZABBIX_HOSTNAME"
    _param_set "HostMetadata" "$(_metadata_create)"

}

function set_zabbix_user_perms() {
    echo "--- SUDOING ZABBIX"

    # adds to sudo 
    if ! text_in_file "%zabbix ALL=(ALL) NOPASSWD: ALL" "/etc/sudoers"; then
        srun "echo '%zabbix ALL=(ALL) NOPASSWD: ALL' | sudo tee -a /etc/sudoers > /dev/null 2>&1" # Adicionando ZABBIX à lista de sudoers
    fi
}

function post_install() {
    echo "--- POST INSTALL"
    srun "systemctl restart zabbix-agent"
    srun "systemctl enable zabbix-agent"
}

# === RUN TIME ===

function run_test() {
    echo "--- RUNNING TEST"
    
    echo "Zabbix information: "
    echo "Server: $ZABBIX_SERVER"
    echo "ServerActive: $ZABBIX_SERVER_ACTIVE"
    echo "Hostname: $ZABBIX_HOSTNAME"
    echo "HostMetadata: $ZABBIX_METADATA"

    exit 0
}

function main() {
    $_TEST && run_test

    # confirm user input
    validate_input

    # install zabbix agent
    install_agent

    # edit the configuration file
    configure_agent

    # i dont like this :(
    set_zabbix_user_perms

    # post install things
    post_install

    # goodbye
    echo "--- DONE"
    exit 0
}

main
