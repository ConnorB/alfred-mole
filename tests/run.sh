#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/src"

test_dir="$(mktemp -d "${TMPDIR:-/tmp}/alfred-mole-tests.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

artifact_path="$("$ROOT_DIR/scripts/build.sh")"
diff -u \
    <(printf '%s\n' commands.def commands.sh icon.png info.plist launch.sh lib.sh) \
    <(unzip -Z1 "$artifact_path" | sort) ||
    fail "artifact contents differ from src/ contract"

mock_bin="$test_dir/bin"
mkdir "$mock_bin"
printf '#!/bin/sh\nexit 0\n' >"$mock_bin/mo"
notification_log="$test_dir/notification.txt"
# shellcheck disable=SC2016 # expanded by the mock
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$MOLE_NOTIFY_TITLE" "$MOLE_NOTIFY_BODY" >>"%s"\n' "$notification_log" >"$mock_bin/osascript"
chmod +x "$mock_bin/mo" "$mock_bin/osascript"

filter_output="$test_dir/commands.json"
PATH="$mock_bin:/usr/bin:/bin" disk_verify=1 "$SOURCE_DIR/commands.sh" >"$filter_output"

# Every argument string the launcher accepts, read through the same helper
# launch.sh uses and run by /bin/bash, the shell the workflow runs under.
accepted_output="$test_dir/accepted.txt"
# shellcheck disable=SC2016 # expanded by the inner shell
/bin/bash -uc '
    . "$1/lib.sh"
    print_accepted() {
        local i=0
        printf "%s\n" "$1"
        while [ "$i" -lt "${#MOD_KEYS[@]}" ]; do
            [ "${MOD_EXTRAS[$i]}" = "-" ] || printf "%s\n" "$1 ${MOD_EXTRAS[$i]}"
            i=$((i + 1))
        done
    }
    for_each_command print_accepted
' _ "$SOURCE_DIR" >"$accepted_output"

python3 - "$filter_output" "$SOURCE_DIR/commands.def" "$SOURCE_DIR/info.plist" "$accepted_output" <<'PY'
import json
import plistlib
import sys
from datetime import datetime

output_path, command_table_path, plist_path, accepted_path = sys.argv[1:]

with open(output_path, encoding="utf-8") as output_file:
    payload = json.load(output_file)

with open(command_table_path, encoding="utf-8") as command_table:
    definitions = [line.rstrip("\n").split("|") for line in command_table if line.strip() and not line.startswith("#")]

assert all(len(fields) == 6 for fields in definitions), "commands.def rows must have six fields"
arguments = [fields[0] for fields in definitions]
assert len(arguments) == len(set(arguments)), "commands.def arguments must be unique"

items = payload["items"]
by_argument = {item["arg"]: item for item in items}
assert set(by_argument) == set(arguments), "script filter rows must match commands.def"

for argument, _title, subtitle, _keywords, mods, _flags in definitions:
    if "DELETES FILES" not in subtitle:
        continue
    modifier_values = dict(entry.split("=", 1) for entry in mods.split(";") if entry)
    assert modifier_values.get("cmd", "").startswith("--dry-run"), f"{argument}: unsafe cmd modifier"
    assert modifier_values.get("alt", "").startswith("--dry-run"), f"{argument}: unsafe alt modifier"

optimize = by_argument["optimize"]
assert "disk verify ON" in optimize["subtitle"]
assert optimize["mods"]["cmd"]["arg"] == "optimize --dry-run"
assert optimize["mods"]["ctrl"]["variables"]["disk_verify_override"] == "off"
assert by_argument["status"]["mods"]["ctrl"]["valid"] is False
assert by_argument["__menu__"]["text"]["copy"] == "mo"
assert "__install__" not in by_argument
assert by_argument["slim"]["mods"]["cmd"]["arg"] == "slim --dry-run"
assert by_argument["completion"]["mods"]["cmd"]["arg"] == "completion --dry-run"

for item in items:
    match_words = set(item["match"].split())
    assert set(item["autocomplete"].split()) <= match_words, f"{item['arg']}: autocomplete would filter out its own row"

offered = set()
for item in items:
    offered.add(item["arg"])
    offered.update(mod["arg"] for mod in item["mods"].values() if mod["valid"])
with open(accepted_path, encoding="utf-8") as accepted_file:
    accepted = set(accepted_file.read().splitlines())
assert offered == accepted, f"launcher and script filter disagree: {sorted(offered ^ accepted)}"

with open(plist_path, "rb") as plist_file:
    plist = plistlib.load(plist_file)

assert plist["bundleid"] == "com.connor.mole-alfred"
assert "\n\n## Modifier keys\n\n- " in plist["readme"]
version_date = datetime.strptime(plist["version"], "%Y.%m.%d")
assert plist["version"] == version_date.strftime("%Y.%m.%d"), "workflow version must use YYYY.0M.0D"
configuration = {entry["variable"]: entry for entry in plist["userconfigurationconfig"]}
assert set(configuration) == {"keyword", "terminal", "disk_verify"}
assert [pair[1] for pair in configuration["terminal"]["config"]["pairs"]] == ["auto", "alfred", "ghostty", "iterm", "wezterm", "kitty", "alacritty", "terminal"]

# The "alfred" choice reaches Alfred's Terminal Command action only through
# a Conditional on the terminal variable, so other choices print nothing.
objects = {obj["type"]: obj for obj in plist["objects"]}
launcher_uid = objects["alfred.workflow.action.script"]["uid"]
conditional = objects["alfred.workflow.utility.conditional"]
terminal_action = objects["alfred.workflow.action.terminalcommand"]
[condition] = conditional["config"]["conditions"]
assert (condition["inputstring"], condition["matchstring"], condition["matchmode"]) == ("{var:terminal}", "alfred", 0)
assert terminal_action["config"]["script"] == "{query}"
assert [c["destinationuid"] for c in plist["connections"][launcher_uid]] == [conditional["uid"]]
[branch] = plist["connections"][conditional["uid"]]
assert (branch["sourceoutputuid"], branch["destinationuid"]) == (condition["uid"], terminal_action["uid"])
PY

if PATH="$mock_bin:/usr/bin:/bin" "$SOURCE_DIR/launch.sh" "__install__" >/dev/null 2>&1; then
    fail "launcher accepted an unknown command"
fi
grep -q '^Mole workflow|This command is not in' "$notification_log" 2>/dev/null ||
    fail "launcher did not report an unknown command"

# With the "alfred" choice the launcher prints the line that Alfred types
# into the user's terminal. --version is used because a real Mole earlier
# on PATH than the mock would run, and --version changes nothing.
alfred_command="$(PATH="$mock_bin:/usr/bin:/bin" terminal=alfred "$SOURCE_DIR/launch.sh" --version)" ||
    fail "launcher failed for Alfred's terminal"
case "$alfred_command" in
    "exec /bin/zsh -lc '"*) ;;
    *) fail "unexpected Alfred terminal command: $alfred_command" ;;
esac

# Terminal, iTerm2, and Alfred's terminal type the launch command into the
# user's login shell. These are the login shells the launcher supports. The
# list is fixed rather than read from /etc/shells, because CI runner images
# add shells such as PowerShell, which does not use POSIX quoting. Standard
# input is empty, so the "Press Return" prompt ends at once.
for supported_shell in /bin/bash /bin/csh /bin/dash /bin/ksh /bin/sh /bin/tcsh /bin/zsh \
    /opt/homebrew/bin/fish /usr/local/bin/fish; do
    [ -x "$supported_shell" ] || continue
    output="$(LC_ALL=C "$supported_shell" -c "$alfred_command" </dev/null 2>&1)" ||
        fail "Terminal command failed in $supported_shell: $output"
    case "$output" in
        *"Mole finished."*) ;;
        *) fail "Terminal command printed the wrong output in $supported_shell: $output" ;;
    esac
done

printf 'All tests passed.\n'
