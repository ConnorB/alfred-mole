#!/bin/bash
#
# Alfred script filter for the Mole CLI.
#
# Alfred filters the results itself (the "Alfred filters results" option in
# info.plist), so this script runs once when the keyword is entered and
# prints every row. It does no matching of its own, which means multi-word
# queries and characters such as * and ? behave the way users expect.
#
# Rows come from commands.def, which launch.sh reads as well. One table
# means a command can never appear in the list without the launcher
# recognising it.

set -u

# shellcheck source=lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# Escape a string for inclusion in a JSON string literal. Uses only
# parameter expansion, so it spawns no subprocesses.
json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//	/\\t}"
    printf '%s' "$value"
}

emit_field() {
    printf '"%s":"%s"' "$1" "$(json_escape "$2")"
}

printf '{"cache":{"seconds":30,"loosereload":true},"items":['

mole_bin="$(find_mole)"

if [ -z "$mole_bin" ]; then
    printf '{'
    emit_field uid "install-mole"
    printf ','
    emit_field title "Mole CLI is not installed"
    printf ','
    emit_field subtitle "Install it with Homebrew: $INSTALL_HINT"
    printf ','
    emit_field match "install mole brew missing setup"
    printf ','
    printf '"valid":false,"text":{'
    emit_field copy "$INSTALL_HINT"
    printf ','
    emit_field largetype "$INSTALL_HINT"
    printf '}}'
    printf ']}'
    exit 0
fi

# MOLE_ENABLE_DISK_VERIFY makes `mo optimize` run diskutil verifyVolume.
# It is off by default because that check can freeze a Mac whose volume has
# APFS inconsistencies, so the state is always shown, never silent.
disk_verify_on=0
[ "${disk_verify:-0}" = "1" ] && disk_verify_on=1

first=true

while IFS='|' read -r arg title subtitle keywords mods flags; do
    case "$arg" in
        '' | '#'*) continue ;;
    esac

    # Show whether disk verification is on, so the setting is never a
    # surprise at the point of running a real optimize.
    row_disk_verify=0
    case " $flags " in
        *" diskverify "*) row_disk_verify=1 ;;
    esac
    if [ "$row_disk_verify" = 1 ]; then
        if [ "$disk_verify_on" = 1 ]; then
            subtitle="$subtitle · disk verify ON"
        fi
    fi

    if [ "$first" = true ]; then first=false; else printf ','; fi

    printf '{'
    emit_field uid "$arg"
    printf ','
    emit_field title "$title"
    printf ','
    emit_field subtitle "$subtitle"
    printf ','
    emit_field arg "$arg"
    printf ','
    emit_field match "$title $subtitle $keywords"
    printf ','
    emit_field autocomplete "$arg"
    printf ','
    printf '"valid":true,'

    display="mo $arg"
    [ "$arg" = "__menu__" ] && display="mo"
    printf '"text":{'
    emit_field copy "$display"
    printf ','
    emit_field largetype "$display"
    printf '},'

    printf '"mods":{'
    mod_first=true
    saved_ifs="$IFS"
    IFS=';'
    for entry in $mods; do
        IFS="$saved_ifs"
        key="${entry%%=*}"
        extra="${entry#*=}"
        [ -z "$key" ] && {
            IFS=';'
            continue
        }

        if [ "$mod_first" = true ]; then mod_first=false; else printf ','; fi

        if [ "$extra" = "-" ]; then
            # Explicitly inert: without this, the modifier would fall
            # through to the default action and run the command for real.
            printf '"%s":{"valid":false,' "$key"
            emit_field subtitle "This command has no modifier action"
            printf '}'
        else
            printf '"%s":{"valid":true,' "$key"
            emit_field arg "$arg $extra"
            printf ','
            emit_field subtitle "Run: mo $arg $extra"
            printf '}'
        fi
        IFS=';'
    done
    IFS="$saved_ifs"

    # Control-Return flips disk verification for this run only, leaving the
    # workflow setting alone. Rows the variable does not affect declare an
    # inert ctrl, so the modifier can never fall through to the plain action.
    if [ "$mod_first" = true ]; then mod_first=false; else printf ','; fi
    if [ "$row_disk_verify" = 1 ]; then
        printf '"ctrl":{"valid":true,'
        emit_field arg "$arg"
        printf ','
        if [ "$disk_verify_on" = 1 ]; then
            emit_field subtitle "Run this once without disk verification"
            printf ',"variables":{'
            emit_field disk_verify_override "off"
            printf '}'
        else
            emit_field subtitle "Run this once with MOLE_ENABLE_DISK_VERIFY=1 · can freeze a Mac with APFS problems"
            printf ',"variables":{'
            emit_field disk_verify_override "on"
            printf '}'
        fi
        printf '}'
    else
        printf '"ctrl":{"valid":false,'
        emit_field subtitle "This command has no modifier action"
        printf '}'
    fi

    printf '}}'
done <"$COMMAND_TABLE"

printf ']}'
