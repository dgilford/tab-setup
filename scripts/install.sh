#!/bin/bash
# Sync this repo's skill files into Claude Code's installed skill location.
#
# Claude runs the skill from ~/.claude/skills/tab-setup, NOT from this repo.
# After pulling changes (e.g. a merged PR), run this so the installed copy
# Claude actually executes matches the repo. Safe to run repeatedly.
#
# Usage: bash scripts/install.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${HOME}/.claude/skills/tab-setup"

echo "Installing tab-setup skill"
echo "  from: $REPO_DIR"
echo "  to:   $DEST"

mkdir -p "$DEST/scripts"

# Skill files Claude reads at runtime (the vscode-extension installs separately).
cp "$REPO_DIR/SKILL.md"            "$DEST/SKILL.md"
cp "$REPO_DIR/README.md"           "$DEST/README.md"
cp "$REPO_DIR/scripts/hook-startup.sh" "$DEST/scripts/hook-startup.sh"
cp "$REPO_DIR/scripts/setup.sh"        "$DEST/scripts/setup.sh"
cp "$REPO_DIR/scripts/sync-all.sh"     "$DEST/scripts/sync-all.sh"
cp "$REPO_DIR/scripts/install.sh"      "$DEST/scripts/install.sh"
cp "$REPO_DIR/scripts/update.sh"       "$DEST/scripts/update.sh"

chmod +x "$DEST/scripts/"*.sh

# Record where this repo lives so `update.sh` knows what to git-pull.
# Written to the skill root (not scripts/) so it doesn't break the verify diff.
printf '%s\n' "$REPO_DIR" > "$DEST/.repo-path"

# Verify the installed scripts match the repo so a silent stale copy can't linger.
if diff -rq "$REPO_DIR/scripts" "$DEST/scripts" >/dev/null; then
    echo "Done — installed scripts match the repo."
else
    echo "Warning: installed scripts still differ from the repo after copy:" >&2
    diff -rq "$REPO_DIR/scripts" "$DEST/scripts" >&2 || true
    exit 1
fi

echo "Note: changes take effect on the next Claude session (the hook fires at SessionStart)."
