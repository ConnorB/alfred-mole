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

# Flags of the row that matched, set by is_known_command.
matched_flags=""

# Build the list of every argument string the script filter can produce:
# each base command plus each of its enabled modifier variants.
is_known_command() {
    local wanted="$1" arg title subtitle keywords mods flags entry key extra saved_ifs

    # title, subtitle, keywords and flags are read only so that the mods
    # field is parsed on its own. Without flags here, mods would absorb it.
    # shellcheck disable=SC2034
    while IFS='|' read -r arg title subtitle keywords mods flags; do
        case "$arg" in
            '' | '#'*) continue ;;
        esac
        if [ "$wanted" = "$arg" ]; then
            matched_flags="$flags"
            return 0
        fi

        saved_ifs="$IFS"
        IFS=';'
        for entry in $mods; do
            IFS="$saved_ifs"
            key="${entry%%=*}"
            extra="${entry#*=}"
            if [ -n "$key" ] && [ "$extra" != "-" ] && [ "$wanted" = "$arg $extra" ]; then
                matched_flags="$flags"
                return 0
            fi
            IFS=';'
        done
        IFS="$saved_ifs"
    done <"$COMMAND_TABLE"

    return 1
}

if [ -z "$selection" ] || ! is_known_command "$selection"; then
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
row_affected_by_disk_verify=0
case " $matched_flags " in
    *" diskverify "*) row_affected_by_disk_verify=1 ;;
esac
if [ "$disk_verify_enabled" = 1 ] && [ "$row_affected_by_disk_verify" = 1 ]; then
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

app_installed() {
    local directory
    for directory in "/Applications" "$HOME/Applications" "/System/Applications/Utilities" "/Applications/Utilities"; do
        [ -d "$directory/$1.app" ] && return 0
    done
    return 1
}

open_with_applescript() {
    /usr/bin/osascript - "$shell_command" "$1" <<'APPLESCRIPT'
on run argv
    set targetCommand to item 1 of argv
    set targetApp to item 2 of argv
    set launchCommand to "exec /bin/zsh -lc " & quoted form of targetCommand
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
