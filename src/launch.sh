#!/bin/bash
#
# Alfred action for the Mole CLI workflow. Opens the selected Mole
# command in a terminal.
#
# The set of permitted commands is derived from commands.def rather than
# repeated here, so the list and the launcher cannot drift apart.

set -u

# shellcheck source=lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

selection="${1:-}"
terminal_choice="${terminal:-auto}"

# MOLE_ENABLE_DISK_VERIFY lets `mo optimize` run diskutil verifyVolume.
# Mole leaves it off by default because that check can freeze a Mac whose
# volume has APFS inconsistencies.
#
# "disk_verify" is the workflow setting. "disk_verify_override" is set by
# the Control-Return modifier and applies to this run only. Both are
# matched against fixed values, so neither can inject anything.
disk_verify_enabled=0
[ "${disk_verify:-0}" = "1" ] && disk_verify_enabled=1
case "${disk_verify_override:-}" in
    on) disk_verify_enabled=1 ;;
    off) disk_verify_enabled=0 ;;
esac

# ---------------------------------------------------------------------------
# Validate the selection against commands.def
# ---------------------------------------------------------------------------

# Set by match_row: whether the selection matched, and that row's flags.
matched=0
matched_flags=""

# Accept the selection only if it is a row's base argument or one of that
# row's enabled modifier variants, the same strings the script filter emits.
# shellcheck disable=SC2329 # invoked indirectly by for_each_command
match_row() {
    local arg="$1" flags="$5" i=0
    [ "$matched" = 1 ] && return 0
    if [ "$selection" = "$arg" ]; then
        matched=1
        matched_flags="$flags"
        return 0
    fi
    while [ "$i" -lt "${#MOD_KEYS[@]}" ]; do
        if [ "${MOD_EXTRAS[$i]}" != "-" ] && [ "$selection" = "$arg ${MOD_EXTRAS[$i]}" ]; then
            matched=1
            matched_flags="$flags"
            return 0
        fi
        i=$((i + 1))
    done
}

is_known_command() {
    for_each_command match_row
    [ "$matched" = 1 ]
}

if [ -z "$selection" ] || ! is_known_command; then
    notify "Mole workflow" "This command is not in the workflow's command list."
    exit 1
fi

# ---------------------------------------------------------------------------
# Build the command line
# ---------------------------------------------------------------------------

args=()
if [ "$selection" != "__menu__" ]; then
    # commands.def uses no quoting or globbing, so word splitting on the
    # argument string is the intended behaviour here.
    # shellcheck disable=SC2206
    args=($selection)
fi

mole_bin="$(find_mole)"
if [ -z "$mole_bin" ]; then
    notify "Mole CLI not found" "Install it with: $INSTALL_HINT"
    exit 1
fi

shell_command=""
if [ "$disk_verify_enabled" = 1 ] && has_flag "$matched_flags" diskverify; then
    # Only rows flagged "diskverify" get the prefix, so it never
    # appears on a command the variable does nothing for. Prefixing the
    # command is the only reliable route: `open` does not hand this
    # process's environment to the terminal it launches.
    shell_command="MOLE_ENABLE_DISK_VERIFY=1 "
fi
printf -v quoted_binary '%q' "$mole_bin"
shell_command="$shell_command$quoted_binary"
# "${args[@]}" alone is an unbound-variable error for an empty array on
# the bash 3.2 that macOS ships, which broke the interactive menu entry.
for argument in ${args[@]+"${args[@]}"}; do
    printf -v quoted_argument '%q' "$argument"
    shell_command="$shell_command $quoted_argument"
done
if [ "$selection" = "__menu__" ]; then window_title="mo"; else window_title="mo $selection"; fi

# Name the terminal window after the command, keep the window open after
# the command exits so that output stays readable, and report a non-zero
# exit status instead of hiding it. The exit code is held in mole_exit
# rather than status, because status is a read-only special parameter in
# zsh and assigning to it aborts the wrapper.
printf -v title_escape '%q' "$window_title"
shell_command="printf '\\033]0;%s\\007' $title_escape; $shell_command; mole_exit=\$?; printf '\\n'; if [ \$mole_exit -ne 0 ]; then printf 'Mole exited with status %s.\\n' \"\$mole_exit\"; else printf 'Mole finished.\\n'; fi; printf 'Press Return to close this window…'; read -r; exit \$mole_exit"

# Terminal, iTerm2, and Alfred's own terminal setting type a line into the
# user's login shell, which can be fish or csh rather than a POSIX shell.
# So that line only starts zsh, with the command in single quotes. Every
# supported shell reads '\'' inside single quotes the same way.
single_quote="'"
launch_command="exec /bin/zsh -lc '${shell_command//$single_quote/$single_quote\\$single_quote$single_quote}'"

if [ "$terminal_choice" = "alfred" ]; then
    # info.plist sends this output to Alfred's Terminal Command action,
    # which opens the terminal chosen in Alfred's Features > Terminal.
    printf '%s' "$launch_command"
    exit 0
fi

app_installed() {
    local directory
    for directory in "/Applications" "$HOME/Applications" "/System/Applications/Utilities" "/Applications/Utilities"; do
        [ -d "$directory/$1.app" ] && return 0
    done
    return 1
}

open_with_applescript() {
    /usr/bin/osascript - "$launch_command" "$1" <<'APPLESCRIPT' >/dev/null
on run argv
    set launchCommand to item 1 of argv
    set targetApp to item 2 of argv
    if targetApp is "iTerm" then
        tell application "iTerm"
            activate
            create window with default profile command launchCommand
        end tell
    else
        tell application "Terminal"
            activate
            do script launchCommand
        end tell
    end if
end run
APPLESCRIPT
}

open_terminal() {
    case "$1" in
        ghostty)
            app_installed "Ghostty" || return 1
            /usr/bin/open -na "Ghostty" --args -e /bin/zsh -lc "$shell_command"
            ;;
        iterm)
            app_installed "iTerm" || return 1
            open_with_applescript "iTerm"
            ;;
        wezterm)
            app_installed "WezTerm" || return 1
            /usr/bin/open -na "WezTerm" --args start -- /bin/zsh -lc "$shell_command"
            ;;
        kitty)
            app_installed "kitty" || return 1
            /usr/bin/open -na "kitty" --args /bin/zsh -lc "$shell_command"
            ;;
        alacritty)
            app_installed "Alacritty" || return 1
            /usr/bin/open -na "Alacritty" --args -e /bin/zsh -lc "$shell_command"
            ;;
        terminal)
            app_installed "Terminal" || return 1
            open_with_applescript "Terminal"
            ;;
        *) return 1 ;;
    esac
}

if [ "$terminal_choice" != "auto" ] && open_terminal "$terminal_choice"; then
    exit 0
fi

for candidate in ghostty iterm wezterm kitty alacritty terminal; do
    open_terminal "$candidate" && exit 0
done

notify "Mole workflow" "No supported terminal could be opened."
exit 1
