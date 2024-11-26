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
add_flag "sa" "server-active" "ServerActive" string
add_flag "s" "server" "Server" string
add_flag "S" "S" "ServerActive and Server" string
add_flag "H" "hostname" "Hostname" string
add_flag "mtdt" "metadata" "HostMetadata" string

# quick server location
add_flag "ovh:HIDDEN" "ovh" "Location: OVH" bool
add_flag "qnax:HIDDEN" "qnax" "Location: QNAX" bool
add_flag "local:HIDDEN" "local" "Location: Local Server" bool

set_description "Zabbix installation utilitary made by Phonevox Group Technology"
parse_flags "$@"

# === FLAGS PARSED ===

# Script-related variables
ZABBIX_CONFIG_FILE_NAME="zabbix_agentd.conf"
ZABBIX_DEFAULT_PATH="/etc/zabbix"
ZABBIX_CONFIG_FILE="$ZABBIX_DEFAULT_PATH/$ZABBIX_CONFIG_FILE_NAME"
ZABBIX_AGENT_VERSION="5.0.42"
ZABBIX_RPM="https://repo.zabbix.com/zabbix/5.0/rhel/7/x86_64/zabbix-agent-$ZABBIX_AGENT_VERSION-1.el7.x86_64.rpm"

# Flag-related configs
hasFlag "d" && _DRY=true || _DRY=false
hasFlag "t" && _TEST=true || _TEST=false
hasFlag "brk" && _BREAK=true || _BREAK=false

$_DRY && (echo "Dry mode is enabled.") || (echo "Dry mode is disabled.")
$_TEST && (echo "Test mode is enabled.") || (echo "Test mode is disabled.")

# === THINGS ===

# "safe-run", abstraction to "run" function, so it can work with our dry mode
# Usage: same as run
function srun() {
    local CMD=$1
    local ACCEPTABLE_EXIT_CODES=$2

    run "$CMD >/dev/null" "$ACCEPTABLE_EXIT_CODES" "$_DRY" "$_SILENT"
}

function validate_input() {
    echo "--- VALIDATING INPUT"
}

# === RUN TIME ===

function run_test() {
    echo "--- RUNNING TEST ---"
    exit 0
}

function main() {
    $_TEST && run_test

    # confirm user input
    validate_input

    # install zabbix agent
    echo "--- INSTALLING ZABBIX AGENT"

    # edit the configuration file
    echo "--- EDITING ZABBIX CONFIGURATION"

    # FIX THE SUDO THING, I DONT WANT ZABBIX TO HAVE UNATTENDED ACCESS TO MY SYSTEM
    echo "--- SUDOING ZABBIX"

    # post install things
    echo "--- POST INSTALL"
    srun "systemctl restart zabbix-agent"
    srun "systemctl enable zabbix-agent"

    # goodbye
    echo "--- DONE"

    exit 0
}

main
