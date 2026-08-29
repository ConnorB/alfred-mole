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
find_mole() {
    command -v mo 2>/dev/null || command -v mole 2>/dev/null || return 1
}

# Show a macOS notification. Text is passed through the environment so
# that quotes in the message cannot break the AppleScript.
notify() {
    MOLE_NOTIFY_TITLE="$1" MOLE_NOTIFY_BODY="$2" /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1
set noticeTitle to system attribute "MOLE_NOTIFY_TITLE"
set noticeBody to system attribute "MOLE_NOTIFY_BODY"
display notification noticeBody with title noticeTitle
APPLESCRIPT
}
