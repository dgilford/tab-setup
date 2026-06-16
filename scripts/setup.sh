#!/bin/bash
# Sets the Claude Code banner color and tab name for a single session.
# Detects the terminal environment and uses the appropriate injection method.
#
# Usage: setup.sh <session_id> [override_name]
#
# Environments supported:
#   iTerm2 (macOS):      iTerm2 escape codes + AppleScript injection
#   VS Code/code-server: pending-color file for the extension to consume
#   Other:               color assigned and reported; apply /color + /rename manually

SESSION_ID="${1:-unknown}"
TRACKING_FILE="${HOME}/.claude/tab-colors.json"
SESSIONS_DIR="${HOME}/.claude/sessions"

[[ ! -f "$TRACKING_FILE" ]] && echo '{}' > "$TRACKING_FILE"

TAB_NAME="${2:-$(basename "$PWD")}"

RESULT=$(python3 - "$TRACKING_FILE" "$SESSION_ID" "$SESSIONS_DIR" "$PWD" "$TAB_NAME" <<'PYEOF'
import json, sys, os, glob, shlex

SEQUENCE = ["red", "blue", "green", "pink", "purple", "cyan", "yellow", "orange"]
COLORS = {
    "red":    (220, 50,  47),
    "blue":   (38,  139, 210),
    "green":  (133, 153, 0),
    "yellow": (181, 137, 0),
    "purple": (108, 113, 196),
    "orange": (203, 75,  22),
    "pink":   (211, 54,  130),
    "cyan":   (42,  161, 152),
}

tracking_file, session_id, sessions_dir, cwd, name = sys.argv[1:]

# Resolve the Claude process PID from session files
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

# Prune dead sessions; skip _last cursor and malformed entries
live, used_colors = {}, set()
for sid, entry in tracking.items():
    if sid == session_id or sid == "_last" or not isinstance(entry, dict):
        continue
    try:
        os.kill(entry.get("pid", 0), 0)
        live[sid] = entry
        used_colors.add(entry.get("color", ""))
    except (OSError, ProcessLookupError):
        pass

# Rotate from last used color so re-invocations within the same session
# advance through the sequence rather than landing on the same slot each time
last_color = tracking.get(session_id, {}).get("color") or tracking.get("_last", "")
try:
    start = (SEQUENCE.index(last_color) + 1) % len(SEQUENCE)
except ValueError:
    start = 0
chosen = next(
    (SEQUENCE[(start + i) % len(SEQUENCE)] for i in range(len(SEQUENCE))
     if SEQUENCE[(start + i) % len(SEQUENCE)] not in used_colors),
    SEQUENCE[start]
)

# Avoid name collision: suffix color only when another live session already holds this name
existing_names = {e.get("name", "") for e in live.values()}
if name in existing_names:
    name = f"{name} ({chosen})"

live[session_id] = {"color": chosen, "pid": claude_pid, "cwd": cwd, "name": name}
live["_last"] = chosen
with open(tracking_file, "w") as f:
    json.dump(live, f, indent=2)

# Transcript writes — belt-and-suspenders for clients that read the JSONL directly
project_hash = cwd.replace("/", "-")
transcript = os.path.expanduser(f"~/.claude/projects/{project_hash}/{session_id}.jsonl")
if os.path.exists(transcript):
    with open(transcript, "a") as f:
        f.write(json.dumps({"type": "agent-color",  "agentColor":  chosen, "sessionId": session_id}) + "\n")
        f.write(json.dumps({"type": "custom-title", "customTitle": name,   "sessionId": session_id}) + "\n")
        f.write(json.dumps({"type": "agent-name",   "agentName":   name,   "sessionId": session_id}) + "\n")

r, g, b = COLORS[chosen]
print(f"CHOSEN_COLOR={chosen}")
print(f"TAB_R={r}")
print(f"TAB_G={g}")
print(f"TAB_B={b}")
print(f"TAB_NAME={shlex.quote(name)}")
print(f"CLAUDE_PID={claude_pid}")
PYEOF
)

if [[ -z "$RESULT" ]] || echo "$RESULT" | grep -q '^error'; then
    echo "error: setup failed — $RESULT"
    exit 1
fi

eval "$RESULT"

if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    CLAUDE_TTY=$(ps -o tty= -p "$CLAUDE_PID" 2>/dev/null | tr -d ' ')
    if [[ -n "$CLAUDE_TTY" && "$CLAUDE_TTY" != "??" && -w "/dev/$CLAUDE_TTY" ]]; then
        {
            printf '\033]6;1;bg;red;brightness;%d\a'   "$TAB_R"
            printf '\033]6;1;bg;green;brightness;%d\a' "$TAB_G"
            printf '\033]6;1;bg;blue;brightness;%d\a'  "$TAB_B"
        } > "/dev/$CLAUDE_TTY"

        # Poll the session JSON until Claude is no longer busy, then inject.
        # Fixed delays race against Claude's response rendering; polling is exact.
        (
            SESSION_JSON=$(python3 -c "
import glob, json, os, sys
for f in glob.glob('${SESSIONS_DIR}/*.json'):
    try:
        d = json.load(open(f))
        if d.get('sessionId') == '${SESSION_ID}':
            print(f); sys.exit(0)
    except: pass
" 2>/dev/null)
            if [[ -n "$SESSION_JSON" ]]; then
                for _ in $(seq 1 60); do
                    STATUS=$(python3 -c "import json; print(json.load(open('$SESSION_JSON')).get('status',''))" 2>/dev/null)
                    [[ "$STATUS" != "busy" ]] && break
                    sleep 0.5
                done
                sleep 0.3
            else
                sleep 5
            fi
            osascript -e "
tell application \"iTerm2\"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if tty of s = \"/dev/${CLAUDE_TTY}\" then
          tell s to write text ((character id 21) & \"/color ${CHOSEN_COLOR}\")
          delay 0.3
          tell s to write text ((character id 21) & \"/rename ${TAB_NAME}\")
          return
        end if
      end repeat
    end repeat
  end repeat
end tell"
        ) &
    else
        echo "warn: no writable TTY for PID $CLAUDE_PID (tty=$CLAUDE_TTY)" >&2
    fi
elif [[ -n "$VSCODE_IPC_HOOK_CLI" ]]; then
    printf 'session_id=%s\ncolor=%s\nname=%s\n' "$SESSION_ID" "$CHOSEN_COLOR" "$TAB_NAME" \
        > "${HOME}/.claude/.pending-color"
else
    echo "note: not in iTerm2 or VS Code — run /color $CHOSEN_COLOR and /rename $TAB_NAME" >&2
fi

echo "color=${CHOSEN_COLOR} name=${TAB_NAME}"
