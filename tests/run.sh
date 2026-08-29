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
chmod +x "$mock_bin/mo"

filter_output="$test_dir/commands.json"
PATH="$mock_bin:/usr/bin:/bin" disk_verify=1 "$SOURCE_DIR/commands.sh" >"$filter_output"

python3 - "$filter_output" "$SOURCE_DIR/commands.def" "$SOURCE_DIR/info.plist" <<'PY'
import json
import plistlib
import sys
from datetime import datetime

output_path, command_table_path, plist_path = sys.argv[1:]

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

with open(plist_path, "rb") as plist_file:
    plist = plistlib.load(plist_file)

assert plist["bundleid"] == "com.connor.mole-alfred"
assert "\n\n## Modifier keys\n\n- " in plist["readme"]
version_date = datetime.strptime(plist["version"], "%Y.%m.%d")
assert plist["version"] == version_date.strftime("%Y.%m.%d"), "workflow version must use YYYY.0M.0D"
configuration = {entry["variable"]: entry for entry in plist["userconfigurationconfig"]}
assert set(configuration) == {"keyword", "terminal", "disk_verify"}
assert [pair[1] for pair in configuration["terminal"]["config"]["pairs"]] == ["auto", "ghostty", "iterm", "wezterm", "kitty", "alacritty", "terminal"]
PY

if "$SOURCE_DIR/launch.sh" "__install__" >/dev/null 2>&1; then
    fail "launcher accepted an unknown command"
fi

if grep -q 'launch_argument' "$SOURCE_DIR/launch.sh" || ! grep -Fq 'set launchCommand to "exec /bin/zsh -lc " & quoted form of targetCommand' "$SOURCE_DIR/launch.sh"; then
    fail "launcher does not use shell-neutral Terminal quoting"
fi

if [ -x /usr/bin/osascript ]; then
    probe_command="printf '%s\\n' 'shell boundary works …'"
    quoted_probe="$(
        LC_ALL=C /usr/bin/osascript - "$probe_command" <<'APPLESCRIPT'
on run argv
    return quoted form of item 1 of argv
end run
APPLESCRIPT
    )"
    while IFS= read -r supported_shell; do
        case "$supported_shell" in
            '' | '#'*) continue ;;
        esac
        [ -x "$supported_shell" ] || continue
        output="$(LC_ALL=C "$supported_shell" -c "exec /bin/zsh -lc $quoted_probe")"
        [ "$output" = "shell boundary works …" ] || fail "Terminal command failed in $supported_shell"
    done </etc/shells
fi

printf 'All tests passed.\n'
