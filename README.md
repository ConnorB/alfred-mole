# Mole CLI for Alfred

This Alfred workflow shows every [Mole](https://github.com/tw93/Mole) command. You can search the list and run a command in a terminal.

Type `mo` in Alfred. Select a command. Then press Return.

## Modifier keys

| Key | Action |
| --- | --- |
| `Return` | Run the command. |
| `Command-Return` | Run the command with `--dry-run`. This option does not change files. |
| `Option-Return` | Run the command with `--dry-run --debug`. |
| `Control-Return` | Change disk verification for one run. This action applies only to optimization rows. |
| `Command-C` | Copy the command to the clipboard. |
| `Command-L` | Show the command in Large Type. |

Some Mole commands can remove files. Alfred marks these rows with `DELETES FILES`.

`Command-Return` and `Option-Return` always add `--dry-run` to these rows. As a result, a modifier key cannot start a file removal.

For other rows, Alfred shows that the modifier has no action.

## Settings

Open the workflow settings in Alfred. Set these values:

- **Keyword** — This word opens the command list. The default word is `mo`.
- **Open commands in** — Select Ghostty, iTerm2, WezTerm, kitty, Alacritty, or Terminal. **Auto-detect** selects the first installed app in this order.
- **Verify disk during optimize** — This setting sets `MOLE_ENABLE_DISK_VERIFY=1`. The setting is off by default.

## Disk verification

If disk verification is off, Mole shows this output:

```text
➤ Disk Health
  → Disk verify skipped (set MOLE_ENABLE_DISK_VERIFY=1 to enable)
```

Disk verification starts kernel-level I/O through `diskutil verifyVolume`. `SIGKILL` cannot stop this I/O.

CAUTION: If you do not need disk verification, keep the setting off. Disk verification can freeze a Mac that has APFS errors.

Use one of these methods:

- **For all runs:** Select **Verify disk during optimize** in the workflow settings. The affected rows show `disk verify ON`.
- **For one run:** Press `Control-Return` on **Optimize macOS** or **Mole Interactive Menu**. If the setting is on, this key turns it off for one run.

The launcher adds `MOLE_ENABLE_DISK_VERIFY=1` to the command line. The launcher adds this variable only to rows that have the `diskverify` flag.

Commands that use `--dry-run` do not start disk verification.

## Requirements

Alfred 5 with the Powerpack is required.

Install the workflow:

1. Download the latest `.alfredworkflow` file from [GitHub Releases](https://github.com/ConnorB/alfred-mole/releases).
2. Open the downloaded file.

Install the Mole CLI:

```sh
brew install mole
```

If Mole is not installed, the workflow shows the installation command. You can copy this command.

## How the workflow works

| File | Purpose |
| --- | --- |
| `src/commands.def` | Defines every command and modifier. Both workflow scripts read this table. |
| `src/commands.sh` | Gives Alfred the JSON command list. Alfred filters this list. |
| `src/launch.sh` | Rejects arguments that are not in `commands.def`. Then it opens the selected terminal. |
| `src/lib.sh` | Contains shared paths, Mole detection, and notifications. |
| `scripts/build.sh` | Creates `dist/Mole-CLI.alfredworkflow` from the files in `src/`. |
| `scripts/lint.sh` | Runs ShellCheck. |
| `tests/run.sh` | Covers the command table, script filter, launcher guard, and workflow archive. |

### Add a command

Add one line to `src/commands.def`:

```text
arg|title|subtitle|keywords|mods|flags
```

- `arg` — These arguments go to `mo`. Use `__menu__` for no arguments.
- `mods` — These `key=extra args` pairs define the modifier actions. Separate the pairs with `;`. If a modifier must do nothing, use `key=-`.
- `flags` — These values define row features. The `diskverify` flag marks a row that uses `MOLE_ENABLE_DISK_VERIFY`.

The launcher reads the table each time. It rejects arguments that are not in the table.

## Versioning

This project uses [Calendar Versioning](https://calver.org/calendar_versioning.html). The version scheme is `YYYY.0M.0D`.

The version uses the release date in UTC. A release tag adds the `v` prefix, for example `v2026.08.29`.

The release workflow writes the tag date to `info.plist`. It stops if the tag does not contain a valid date.

## Development

Before you submit a change, run these commands:

```sh
./scripts/lint.sh
./tests/run.sh
```

The test script also creates the installable workflow. The checks require ShellCheck and Python 3.

GitHub Actions runs these checks for every push and pull request.

If you push a valid CalVer tag, GitHub creates a release. The release contains the `.alfredworkflow` file.
