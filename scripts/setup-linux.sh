#!/bin/bash
# Linux adaptation of tab-setup: assigns a banner color and session name by
# writing agent-color/custom-title to the transcript AND injecting /color +
# /rename into the Claude process's PTY after a short delay (same mechanism
# as the macOS version's AppleScript, just using the PTY directly).
#
# Usage: setup-linux.sh <session_id> [override_name]

SESSION_ID="${1:-unknown}"
TRACKING_FILE="${HOME}/.claude/tab-colors.json"
SESSIONS_DIR="${HOME}/.claude/sessions"

[[ ! -f "$TRACKING_FILE" ]] && echo '{}' > "$TRACKING_FILE"

TAB_NAME="${2:-$(basename "$PWD")}"

RESULT=$(python3 - "$TRACKING_FILE" "$SESSION_ID" "$SESSIONS_DIR" "$PWD" "$TAB_NAME" <<'PYEOF'
import json, sys, os, glob

# Greedy farthest-point sequence using Claude Code banner color names.
# Each step maximises perceptual distance from prior picks.
# "red" replaced with "crimson" (Claude Code doesn't recognise "red").
SEQUENCE = ["crimson", "blue", "green", "pink", "purple", "cyan", "yellow", "orange"]

tracking_file, session_id, sessions_dir, cwd, name = sys.argv[1:]

# Resolve the long-lived Claude process PID
claude_pid = None
for f in glob.glob(os.path.join(sessions_dir, "*.json")):
    try:
        data = json.load(open(f))
        if data.get("sessionId") == session_id:
            claude_pid = data.get("pid")
            break
    except Exception:
        pass

if claude_pid is None:
    print(f"error: no session found for {session_id}", file=sys.stderr)
    sys.exit(1)

try:
    tracking = json.load(open(tracking_file))
except Exception:
    tracking = {}

# Remove stale entry for this session, prune dead PIDs
tracking.pop(session_id, None)
live, used_colors = {}, set()
for sid, entry in tracking.items():
    try:
        os.kill(entry.get("pid", 0), 0)
        live[sid] = entry
        used_colors.add(entry.get("color", ""))
    except (OSError, ProcessLookupError):
        pass

# Claim the earliest sequence slot not already in use
chosen = next((c for c in SEQUENCE if c not in used_colors), SEQUENCE[0])

live[session_id] = {"color": chosen, "pid": claude_pid, "cwd": cwd, "name": name}
with open(tracking_file, "w") as f:
    json.dump(live, f, indent=2)

# Write to live transcript (belt-and-suspenders for clients that read it)
project_hash = cwd.replace("/", "-")
transcript = os.path.expanduser(f"~/.claude/projects/{project_hash}/{session_id}.jsonl")
if os.path.exists(transcript):
    with open(transcript, "a") as f:
        f.write(json.dumps({"type": "agent-color",  "agentColor":  chosen, "sessionId": session_id}) + "\n")
        f.write(json.dumps({"type": "custom-title", "customTitle": name,   "sessionId": session_id}) + "\n")
        f.write(json.dumps({"type": "agent-name",   "agentName":   name,   "sessionId": session_id}) + "\n")

print(f"CHOSEN_COLOR={chosen}")
print(f"TAB_NAME={name}")
print(f"CLAUDE_PID={claude_pid}")
PYEOF
)

if [[ -z "$RESULT" ]] || echo "$RESULT" | grep -q '^error'; then
    echo "error: setup failed — $RESULT"
    exit 1
fi

eval "$RESULT"


echo "color=${CHOSEN_COLOR} name=${TAB_NAME}"
