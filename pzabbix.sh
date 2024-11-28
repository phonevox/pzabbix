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
APP_VERSION="v0.1.2"

source $CURRDIR/lib/useful.sh
source $CURRDIR/lib/easyflags.sh
source $CURRDIR/lib/versioncontrol.sh

# === FLAGS BELOW ===

# General flags
add_flag "d" "dry" "Do NOT make changes to the system" bool
add_flag "t" "test" "Test mode" bool
add_flag "v" "verbose" "Verbose mode" bool

# Zabbix configuration flags
add_flag "sa" "server-active" "Zabbix: ServerActive" ip/domain
add_flag "s" "server" "Zabbix: Server" ip/domain
add_flag "S" "S" "Zabbix: ServerActive and Server" ip/domain
add_flag "H" "hostname" "Zabbix: Hostname" string
add_flag "m" "metadata" "Zabbix: HostMetadata, maximum of 255 characters" string
add_flag "p" "provider" "Phonevox: Server location by Phonevox's lenses (ovh,aws,qnax,local)" string

# script versioning
add_flag "V" "version" "Show the script version" bool
add_flag "U:HIDDEN" "update" "Update the script to the latest version" bool
add_flag "FU:HIDDEN" "force-update" "Forcefully updates the script to the latest version" bool

set_description "Zabbix installation utilitary made by Phonevox Group Technology"
parse_flags "$@"

# === FLAGS PARSED ===


# Used in Zabbix param checking (on file configuration)
declare -A parameter_exist
declare -A parameter_value

# Zabbix-related variables
ZABBIX_CONFIG_FILE_NAME="zabbix_agentd.conf"
ZABBIX_DEFAULT_PATH="/etc/zabbix"
ZABBIX_CONFIG_FILE="$ZABBIX_DEFAULT_PATH/$ZABBIX_CONFIG_FILE_NAME"

ZABBIX_VERSION="5.0"
ZABBIX_RPM="https://repo.zabbix.com/zabbix/$ZABBIX_VERSION/rhel/$SYSTEM_OS_VERSION/x86_64/zabbix-release-latest.el$SYSTEM_OS_VERSION.noarch.rpm"

ZABBIX_SERVER=""
ZABBIX_SERVER_ACTIVE=""
ZABBIX_HOSTNAME=""
ZABBIX_METADATA=""

# Flag-related configs
if hasFlag "V"; then echo "$APP_VERSION"; exit 0; fi
hasFlag "d" && _DRY=true || _DRY=false
hasFlag "t" && _TEST=true || _TEST=false
hasFlag "v" && _VERBOSE=true || _VERBOSE=false
hasFlag "U" && _UPDATE=true || _UPDATE=false
hasFlag "FU" && _FORCE_UPDATE=true || _FORCE_UPDATE=false
hasFlag "s" && ZABBIX_SERVER=$(getFlag "s")
hasFlag "sa" && ZABBIX_SERVER_ACTIVE=$(getFlag "sa") || ZABBIX_SERVER_ACTIVE=$ZABBIX_SERVER
hasFlag "S" && ZABBIX_SERVER=$(getFlag "S"); ZABBIX_SERVER_ACTIVE=$ZABBIX_SERVER
hasFlag "H" && ZABBIX_HOSTNAME=$(getFlag "H")
hasFlag "m" && ZABBIX_METADATA=$(getFlag "m")
hasFlag "p" && CLOUD_PROVIDER=$(getFlag "p")

# Additional information from system
SYSTEM_OS_ID=$(get_os_info "ID") #centos|rocky|debian|ubuntu
SYSTEM_OS_VERSION=$(get_os_info "VERSION_ID") # 7|8.0|18|22 etc... (version number)
SYSTEM_OS="$SYSTEM_OS_ID-$SYSTEM_OS_VERSION" # centos-7|rocky-8.0 etc...
SYSTEM_HOSTNAME=$(hostname)
SYSTEM_MACHINE_ID=$(cat /etc/machine-id)
ASTERISK_VERSION=$(asterisk -V | awk -F"Asterisk " '{print $2}') # integer
CLOUD_PROVIDER=$(determine_cloud_provider)

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

    if [[ ! "$ZABBIX_SERVER" != "" ]]; then
        echo "• no zabbix server detected" #this IS required and should be set
        echo "ERROR: Please set your Zabbix server address"
        exit 1
    fi
    echo "$(colorir verde "•") server: $ZABBIX_SERVER"

    if [[ ! "$ZABBIX_SERVER_ACTIVE" != "" ]]; then
        echo "$(colorir vermelho "•") > no active zabbix server detected" #not required
    fi
    echo "$(colorir verde "•") server active: $ZABBIX_SERVER_ACTIVE"

    if [[ ! "$ZABBIX_HOSTNAME" != "" ]]; then

        # by default always assumes machine-id
        PROBABLE_HOSTNAME=$SYSTEM_MACHINE_ID

        # CHORE(adrian): report back if you failed to trust the detected provider's hostname!
        if [[ "$CLOUD_PROVIDER" == "ovh" ]]; then
            echo "• OVH cloud detected."
            PROBABLE_HOSTNAME=$(echo $SYSTEM_HOSTNAME | grep -oE "^vps-[a-z0-9]+") # vps-da2bcebf
            PROBABLE_HOSTNAME_CHARCOUNT=$(echo -n $PROBABLE_HOSTNAME | wc -c)
            [[ ! "$PROBABLE_HOSTNAME_CHARCOUNT" -eq 12 ]] && ZABBIX_HOSTNAME=$PROBABLE_HOSTNAME

        elif [[ "$CLOUD_PROVIDER" == "qnax" ]]; then
            echo "• QNax cloud detected."
            PROBABLE_HOSTNAME=$(echo $SYSTEM_HOSTNAME | grep -oE "^SRV-[0-9]+$") # SRV-1699030926
            PROBABLE_HOSTNAME_CHARCOUNT=$(echo -n $PROBABLE_HOSTNAME | wc -c)
            [[ "$PROBABLE_HOSTNAME_CHARCOUNT" -eq 14 ]] && ZABBIX_HOSTNAME=$PROBABLE_HOSTNAME

        # elif [[ "$CLOUD_PROVIDER" == "aws" ]]; then
        else
            echo "$(colorir laranja "•") > no cloud provider detected. assuming local machine"
            PROBABLE_HOSTNAME=$SYSTEM_MACHINE_ID
        fi

        # cloudprovider hostname detection failed, assume machine-id and inform user
        if [[ "$CLOUD_PROVIDER" != "local" && "$PROBABLE_HOSTNAME" == "$MACHINE_ID" ]]; then
            echo "$(colorir vermelho "•") > could not determine cloud provider hostname, assuming machine-id"
            PROBABLE_HOSTNAME=$SYSTEM_MACHINE_ID
        fi

        ZABBIX_HOSTNAME=$PROBABLE_HOSTNAME
    fi
    echo "$(colorir verde "•") hostname: $PROBABLE_HOSTNAME"

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

# v RELATED TO configure_agent

# checks if parameter exists, is duplicate, etc..
# usage: _param_check "<zabbix_parameter>"
function _param_check() {
    local PARAMETER=$1

    function _param_has_duplicate() {
        # this func adds info to associative-array 'parameter_exist'
        local PARAMETER=$1
        local QTY_MATCH_LINES=$(cat $ZABBIX_CONFIG_FILE | grep -I "^$PARAMETER=" | wc -l)

        [[ $QTY_MATCH_LINES > 1 ]] && return 0
        [[ $QTY_MATCH_LINES < 1 ]] && (parameter_exist[$PARAMETER]+=false) || (parameter_exist[$PARAMETER]+=true)
        return 1
    }

    function _param_is_empty() {
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
function _param_set() {
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
# use in subshell
# usage: metadata=$(_metadata_create)
function _metadata_create() {
    local METADATA_CONTENT=""
    function _metadata_append() {
        local NEW_METADATA=$1
        METADATA_CONTENT+="$NEW_METADATA "
    }

    # NOTE(adrian): if you need more characters for metadata content
    # try making the default information smaller like: os:1 os:2 os:3 and 
    # map those to "windows, linux, macos" on zabbix autoreg

    # default metadata
    _metadata_append "l:$CLOUD_PROVIDER"
    _metadata_append "os:linux"
    _metadata_append "osn:$SYSTEM_OS"

    # dependant metadata (depends on other things existing in the system)
    if [[ ! -z "$ASTERISK_VERSION" ]]; then
        # has asterisk. here should be all the metadata related to his asterisk thing
        _metadata_append "av:$ASTERISK_VERSION"
    fi

    # user metadata. should be the last thing, because it can exceed the 255 char limit
    _metadata_append "$ZABBIX_METADATA"

    if [[ ${#METADATA_CONTENT} -gt 255 ]]; then
        exit 1
    fi

    echo $METADATA_CONTENT
}

# ^ RELATED TO configure_agent

function configure_agent() {
    echo "--- EDITING ZABBIX CONFIGURATION"

    # validates expected files exists
    ! [ -d $ZABBIX_DEFAULT_PATH ] && (echo "ERROR: $ZABBIX_DEFAULT_PATH does not exist" && exit 1) || (echo "ZABBIX_DEFAULT_PATH found")
    ! [ -f $ZABBIX_CONFIG_FILE ] && (echo "ERROR: $ZABBIX_CONFIG_FILE does not exist" && exit 1) || (echo "ZABBIX_CONFIG_FILE found")

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
    
    echo -e "\n\n"
    validate_input
    echo ""
    echo "       --- Zabbix information --- "
    echo "          Server : $ZABBIX_SERVER"
    echo "    ServerActive : $ZABBIX_SERVER_ACTIVE"
    echo "        Hostname : $ZABBIX_HOSTNAME"
    echo "    HostMetadata : $ZABBIX_METADATA"
    echo "_metadata_create : $(_metadata_create)"
    echo "  Cloud Provider : $CLOUD_PROVIDER"
    echo "Asterisk Version : $ASTERISK_VERSION"
    # echo "              OS : $(get_os)"
    # echo "         OS INFO : $(get_os_info "ID")-$(get_os_info "VERSION_ID")"
    echo ""


    exit 0
}

function main() {
    $_DRY && (echo "Dry mode is enabled.") || (echo "Dry mode is disabled.")
    $_TEST && (echo "Test mode is enabled.") || (echo "Test mode is disabled.")
    $_VERBOSE && (echo "Verbose mode is enabled.") || (echo "Verbose mode is disabled.")
    $_TEST && run_test
    $_UPDATE && check_for_updates

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
