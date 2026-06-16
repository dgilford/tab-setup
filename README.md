# tab-setup

A Claude Code skill that gives each terminal tab a unique high-contrast color and renames it after its working directory — automatically, across all open sessions.

## What it does

- Injects **`/color`** and **`/rename`** into the Claude Code session to update the banner
- Tracks session→color assignments in `~/.claude/tab-colors.json` and prunes dead ones automatically
- Assigns colors from a pre-computed high-contrast sequence so adjacent sessions never look similar
- Avoids name collisions: if two sessions share a project name, the second gets `project (color)` appended
- Dead sessions are pruned lazily on the next run — every reader drops entries whose process is gone, so no background process is needed

## Supported environments

| Environment | Banner color | Tab background | Auto-inject |
|---|---|---|---|
| iTerm2 (macOS) | ✅ `/color` via AppleScript | ✅ iTerm2 escape codes | ✅ ~4s delay |
| VS Code / code-server | ✅ `/color` via extension | ✅ `workbench.action.terminal.changeColor` | ✅ polls until idle |
| Other terminals | ✅ reported to user | ❌ | ❌ manual |

## Color sequence

Colors are assigned in this order (greedy farthest-point in RGB space):

`red → blue → green → pink → purple → cyan → yellow → orange`

With `/tab-setup all`, sessions are sorted oldest-first so the longest-running session always anchors at red. With `/tab-setup` (single session), the sequence rotates from the last assigned color so re-invocations always advance.

## Installation

```bash
cp -r tab-setup ~/.claude/skills/tab-setup
chmod +x ~/.claude/skills/tab-setup/scripts/*.sh
```

### Updating

Claude runs the skill from `~/.claude/skills/tab-setup`, **not** from this repo, so
pulling changes (or merging a PR) does not update the copy Claude executes. After any
`git pull`, re-sync the installed copy:

```bash
bash scripts/install.sh
```

It copies the skill files into place, verifies the installed scripts match the repo,
and warns if anything is still stale. Changes take effect on the **next** Claude session.

Once installed, you can also update from inside Claude — `install.sh` records the repo
location, so this pulls the latest and re-installs in one step:

```
/tab-setup update
```

**VS Code / code-server only** — install the companion extension once:

```bash
bash ~/.claude/skills/tab-setup/vscode-extension/install.sh
```

Then reload the VS Code window.

## Usage

| Command | Effect |
|---|---|
| `/tab-setup` | Color + rename this tab from its CWD |
| `/tab-setup billing` | Color this tab, name it "billing" |
| `/tab-setup all` | Recolor + rename every active Claude session |

## Auto-startup (optional)

By default you trigger this skill by typing `/tab-setup`. If you'd rather have every
session color itself automatically at boot — no typing — register `hook-startup.sh` as
a **Claude Code `SessionStart` hook**.

> **Note:** this is a change to **Claude Code's own configuration**, not to the skill.
> The skill only provides the script; the hook is what makes Claude run it on startup.
> Installing/updating the skill does **not** enable auto-startup — you opt in here, once.

### 1. Edit your Claude Code settings

Open `~/.claude/settings.json` (global, applies to every project) and add a
`SessionStart` hook. **Merge** it into any existing `hooks` block — don't overwrite
hooks you already have (e.g. `Notification`, `Stop`):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/tab-setup/scripts/hook-startup.sh"
          }
        ]
      }
    ]
  }
}
```

For a per-project hook instead of global, put the same block in
`<project>/.claude/settings.json`.

### 2. Verify it's wired up

```bash
# Should print the command string with no error:
jq -e '.hooks.SessionStart[].hooks[].command' ~/.claude/settings.json

# Smoke-test the script the way the hook calls it (should exit 0):
echo '{}' | bash ~/.claude/skills/tab-setup/scripts/hook-startup.sh
```

The hook takes effect on the **next** session you start (not the current one). You can
review or disable it anytime from the `/hooks` menu, or by deleting the `SessionStart`
block. A broken `settings.json` silently disables *all* settings in that file, so keep
the JSON valid.

### How it works

The script works around the `CLAUDE_SESSION_ID=''` limitation in `SessionStart` hooks by
walking the PPID chain (hook → shell → claude) to identify the Claude process, then
dispatches to the correct injection mechanism based on the detected environment. No
`/dev/tty` access required — works in code-server and JupyterHub too.

### Tuning

Tune the delay if `/color` fires before Claude's first prompt is ready (default `4`):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "TAB_SETUP_INJECT_DELAY=6 bash ~/.claude/skills/tab-setup/scripts/hook-startup.sh"
          }
        ]
      }
    ]
  }
}
```

Optionally set `ANTHROPIC_API_KEY` in the `env` block of `settings.json` for
Haiku-generated session names (otherwise it falls back to a deterministic wordlist).

## Requirements

- Claude Code CLI
- Python 3 (stdlib only — no pip dependencies)
- **iTerm2** (macOS) — for tab background color and auto-injection
- **VS Code extension** (code-server / VS Code) — for auto-injection; see installation above
