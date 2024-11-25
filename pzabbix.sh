#!/bin/bash

FULL_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
CURRDIR="$(dirname "$FULL_SCRIPT_PATH")"
SCRIPT_NAME="$(basename "$FULL_SCRIPT_PATH")"



source $CURRDIR/lib/useful.sh
source $CURRDIR/lib/easyflags.sh

SYSTEM_OS=$(get_os)

add_flag "d" "dry" "Do NOT make changes to the system" bool
add_flag "t" "test" "Test mode" bool
add_flag "v" "verbose" "Verbose mode" bool

set_description "Test"
parse_flags "$@"

hasFlag "d" && _DRY=true || _DRY=false
hasFlag "t" && _TEST=true || _TEST=false
