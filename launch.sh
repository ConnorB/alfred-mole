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

# The shell used inside the terminal window. /bin/zsh is present on every
# supported macOS release, and the quoting below is zsh-compatible.
readonly LOGIN_SHELL="/bin/zsh"

selection="${1:-}"

# The terminal to use, set by the workflow configuration in Alfred.
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
            ''|'#'*) continue ;;
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
    done < "$COMMAND_TABLE"

    return 1
}

if [ -z "$selection" ]; then
    notify "Mole workflow" "No action was selected."
    exit 1
fi

if [ "$selection" != "__install__" ] && ! is_known_command "$selection"; then
    notify "Mole workflow" "The selected action was not recognised."
    exit 1
fi

# ---------------------------------------------------------------------------
# Build the command line
# ---------------------------------------------------------------------------

args=()
if [ "$selection" != "__menu__" ] && [ "$selection" != "__install__" ]; then
    # commands.def uses no quoting or globbing, so word splitting on the
    # argument string is the intended behaviour here.
    # shellcheck disable=SC2206
    args=($selection)
fi

if [ "$selection" = "__install__" ]; then
    brew_bin="$(command -v brew 2>/dev/null || true)"
    if [ -z "$brew_bin" ]; then
        notify "Homebrew not found" "Install Homebrew from brew.sh, then run: $INSTALL_HINT"
        exit 1
    fi
    printf -v shell_command '%q install mole' "$brew_bin"
    window_title="Installing Mole"
else
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
fi

# Name the terminal window after the command, keep the window open after
# the command exits so that output stays readable, and report a non-zero
# exit status instead of hiding it. The exit code is held in mole_exit
# rather than status, because status is a read-only special parameter in
# zsh and assigning to it aborts the wrapper.
printf -v title_escape '%q' "$window_title"
shell_command="printf '\\033]0;%s\\007' $title_escape; $shell_command; mole_exit=\$?; printf '\\n'; if [ \$mole_exit -ne 0 ]; then printf 'Mole exited with status %s.\\n' \"\$mole_exit\"; else printf 'Mole finished.\\n'; fi; printf 'Press Return to close this window…'; read -r; exit \$mole_exit"

printf -v launch_argument '%q' "$shell_command"
readonly full_invocation="$LOGIN_SHELL -lc $launch_argument"

# ---------------------------------------------------------------------------
# Open a terminal
# ---------------------------------------------------------------------------

app_installed() {
    local directory
    for directory in "/Applications" "$HOME/Applications" "/System/Applications/Utilities" "/Applications/Utilities"; do
        [ -d "$directory/$1.app" ] && return 0
    done
    return 1
}

open_with_applescript() {
    MOLE_COMMAND="$full_invocation" MOLE_APP="$1" /usr/bin/osascript <<'APPLESCRIPT'
set targetCommand to system attribute "MOLE_COMMAND"
set targetApp to system attribute "MOLE_APP"
if targetApp is "iTerm" then
    tell application "iTerm"
        activate
        create window with default profile command targetCommand
    end tell
else
    tell application "Terminal"
        activate
        do script targetCommand
    end tell
end if
APPLESCRIPT
}

open_terminal() {
    case "$1" in
        ghostty)
            app_installed "Ghostty" || return 1
            /usr/bin/open -na "Ghostty" --args -e "$LOGIN_SHELL" -lc "$shell_command"
            ;;
        iterm)
            app_installed "iTerm" || return 1
            open_with_applescript "iTerm"
            ;;
        wezterm)
            app_installed "WezTerm" || return 1
            /usr/bin/open -na "WezTerm" --args start -- "$LOGIN_SHELL" -lc "$shell_command"
            ;;
        kitty)
            app_installed "kitty" || return 1
            /usr/bin/open -na "kitty" --args "$LOGIN_SHELL" -lc "$shell_command"
            ;;
        alacritty)
            app_installed "Alacritty" || return 1
            /usr/bin/open -na "Alacritty" --args -e "$LOGIN_SHELL" -lc "$shell_command"
            ;;
        terminal)
            open_with_applescript "Terminal"
            ;;
        *)
            return 1
            ;;
    esac
}

if [ "$terminal_choice" != "auto" ]; then
    if open_terminal "$terminal_choice"; then
        exit 0
    fi
    notify "Terminal not available" "${terminal_choice} could not be opened. Falling back to the first terminal found."
fi

for candidate in ghostty iterm wezterm kitty alacritty terminal; do
    if open_terminal "$candidate"; then
        exit 0
    fi
done

notify "Mole workflow" "No supported terminal could be opened."
exit 1
