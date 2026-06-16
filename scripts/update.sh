#!/bin/bash
# Pull the latest skill from its git repo and re-install it into Claude's
# skill directory. Backs `/tab-setup update`.
#
# The repo location is recorded by install.sh at ~/.claude/skills/tab-setup/.repo-path,
# so this works regardless of where the repo was cloned.
#
# Usage: bash scripts/update.sh
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_PATH_FILE="${SKILL_DIR}/.repo-path"

if [[ ! -f "$REPO_PATH_FILE" ]]; then
    echo "error: no recorded repo path ($REPO_PATH_FILE)." >&2
    echo "Run 'bash scripts/install.sh' from the repo once to record it." >&2
    exit 1
fi

REPO_DIR="$(cat "$REPO_PATH_FILE")"
if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "error: recorded repo path is not a git checkout: $REPO_DIR" >&2
    exit 1
fi

echo "Updating tab-setup from $REPO_DIR"

# Refuse to pull over uncommitted work — surface it instead of clobbering.
if [[ -n "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    echo "error: repo has uncommitted changes — commit or stash them first:" >&2
    git -C "$REPO_DIR" status --short >&2
    exit 1
fi

BEFORE="$(git -C "$REPO_DIR" rev-parse HEAD)"
git -C "$REPO_DIR" pull --ff-only
AFTER="$(git -C "$REPO_DIR" rev-parse HEAD)"

if [[ "$BEFORE" == "$AFTER" ]]; then
    echo "Already up to date ($AFTER)."
else
    echo "Updated $BEFORE -> $AFTER"
fi

# Re-install from the (now current) repo. install.sh verifies the copy.
bash "$REPO_DIR/scripts/install.sh"
