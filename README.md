# Mole CLI for Alfred

Browse, search, and run every [Mole](https://github.com/tw93/Mole) command from Alfred.

Type `mo` in Alfred, filter the list, and press Return to open the command
in your terminal.

## Modifier keys

| Key | Action |
| --- | --- |
| `Return` | Run the command |
| `Command-Return` | Run the command with `--dry-run`, which changes nothing |
| `Option-Return` | Run the command with `--dry-run --debug` |
| `Control-Return` | Optimize rows only: flip disk verification for this run |
| `Command-C` | Copy the command to the clipboard |
| `Command-L` | Show the command in Large Type |

Rows that can delete files are labelled `DELETES FILES` in the result list.
Every one of those rows defines its own `Command-Return` and `Option-Return`
behaviour, so a modifier key can never start a real deletion by mistake.
Rows that have no modifier action say so instead of falling back to the
plain command.

## Configuration

Open the workflow in Alfred and press the configuration button to set:

- **Keyword** — the word that opens the command list. The default is `mo`.
- **Open commands in** — Ghostty, iTerm2, WezTerm, kitty, Alacritty, or
  Terminal. **Auto-detect** uses the first of those that is installed.
- **Verify disk during optimize** — sets `MOLE_ENABLE_DISK_VERIFY=1`. Off by
  default. See below.

## Disk verification

`mo optimize` normally prints:

```
➤ Disk Health
  → Disk verify skipped (set MOLE_ENABLE_DISK_VERIFY=1 to enable)
```

Mole skips the check because `diskutil verifyVolume` starts kernel-level I/O
that `SIGKILL` cannot interrupt. On a volume with APFS inconsistencies this
can freeze the Mac. Turn it on only when you want that check.

Two ways to enable it:

- **Permanently** — tick *Verify disk during optimize* in the workflow
  configuration. Affected rows then read `disk verify ON` in their subtitle,
  so the setting is never silent.
- **For one run** — press `Control-Return` on the **Optimize macOS** or
  **Mole Interactive Menu** row. This does not change the setting. When the
  setting is already on, `Control-Return` runs that once *without*
  verification.

The variable is prefixed onto the command line, because `open` does not pass
this workflow's environment to the terminal it launches. It is added only to
rows flagged `diskverify` in `commands.def`, so it never appears on a command
it does nothing for. `--dry-run` runs still skip the check; that is Mole's
own behaviour.

## Requirements

Install the Mole CLI:

```sh
brew install mole
```

If Mole is not installed, the workflow shows one row that offers to install
it with Homebrew.

## How it works

| File | Purpose |
| --- | --- |
| `commands.def` | The command table. Both scripts read it, so the list and the launcher cannot drift apart. |
| `commands.sh` | The Alfred script filter. Prints every row as JSON. Alfred does the matching. |
| `launch.sh` | The action. Validates the selection against `commands.def` and opens a terminal. |
| `lib.sh` | Shared helpers: `PATH` setup, Mole discovery, notifications. |

### Adding a command

Add one line to `commands.def`:

```
arg|title|subtitle|keywords|mods|flags
```

- `arg` — the arguments passed to `mo`. Use `__menu__` for no arguments.
- `mods` — `;`-separated `key=extra args` pairs, where `key` is `cmd` or
  `alt`. Use `key=-` to make that modifier inert.
- `flags` — space-separated row capabilities. `diskverify` marks a row that
  `MOLE_ENABLE_DISK_VERIFY` changes.

The launcher accepts the new row automatically. It refuses any argument
that the table does not describe, so the workflow cannot be made to run an
arbitrary command.
