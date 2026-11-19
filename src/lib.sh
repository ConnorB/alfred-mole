#!/bin/bash
#
# Shared helpers for the Mole Alfred workflow. Sourced by commands.sh
# (the script filter) and launch.sh (the action).

# Alfred runs workflow scripts with a minimal PATH, so add the locations
# where Mole is normally installed.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/opt/local/bin:$PATH"

# Used by the scripts that source this file.
# shellcheck disable=SC2034
WORKFLOW_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
COMMAND_TABLE="$WORKFLOW_DIR/commands.def"
# shellcheck disable=SC2034
INSTALL_HINT="brew install mole"

# Print the path of the Mole binary, or return 1 if it is not installed.
# "mole" is tried first because "mo" is a short, generic name that another
# tool on the PATH can also use.
find_mole() {
    command -v mole 2>/dev/null || command -v mo 2>/dev/null || return 1
}

# Call the function named by $1 once for each row of commands.def, as
#   $1 arg title subtitle keywords flags
# Before each call, MOD_KEYS and MOD_EXTRAS hold the row's modifiers in
# order. An extra of "-" marks a modifier that must do nothing.
#
# commands.sh and launch.sh both read the table through this function, so
# the launcher accepts exactly the arguments that the script filter offers.
for_each_command() {
    local callback="$1" arg title subtitle keywords mods flags entry
    local mod_entries
    while IFS='|' read -r arg title subtitle keywords mods flags; do
        case "$arg" in
            '' | '#'*) continue ;;
        esac
        mod_entries=()
        [ -n "$mods" ] && IFS=';' read -r -a mod_entries <<<"$mods"
        MOD_KEYS=()
        MOD_EXTRAS=()
        # ${array[@]+...} guards the empty array, which is an unbound-variable
        # error under set -u in the bash 3.2 that macOS ships.
        for entry in ${mod_entries[@]+"${mod_entries[@]}"}; do
            [ -n "${entry%%=*}" ] || continue
            MOD_KEYS+=("${entry%%=*}")
            MOD_EXTRAS+=("${entry#*=}")
        done
        "$callback" "$arg" "$title" "$subtitle" "$keywords" "$flags"
    done <"$COMMAND_TABLE"
}

# Return 0 if the space-separated flag list $1 contains flag $2.
has_flag() {
    case " $1 " in
        *" $2 "*) return 0 ;;
    esac
    return 1
}

# Show a macOS notification. Text is passed through the environment so
# that quotes in the message cannot break the AppleScript. osascript is
# found through PATH, so tests can replace it.
notify() {
    MOLE_NOTIFY_TITLE="$1" MOLE_NOTIFY_BODY="$2" osascript <<'APPLESCRIPT' >/dev/null 2>&1
set noticeTitle to system attribute "MOLE_NOTIFY_TITLE"
set noticeBody to system attribute "MOLE_NOTIFY_BODY"
display notification noticeBody with title noticeTitle
APPLESCRIPT
}
