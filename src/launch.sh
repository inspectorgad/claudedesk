#!/bin/bash
# claudedesk launcher
#
# Lives at Contents/MacOS/launch inside each "Claude <Profile>.app" bundle.
# Reads its profile from the bundle's Info.plist, then either brings the
# already-running Claude Desktop instance for that profile to the front or
# starts a new one with an isolated --user-data-dir.
#
# Flags:
#   --dry-run   Resolve everything and print what would happen; change nothing.
#
# Environment overrides (used by tests and for troubleshooting):
#   CLAUDEDESK_PROFILE_NAME   overrides the plist profile name
#   CLAUDEDESK_PROFILE_DIR    overrides the plist profile dir ("" = default)
#   CLAUDEDESK_CLAUDE_APP     path to Claude.app
#   CLAUDEDESK_LOG            log file (default ~/Library/Logs/claudedesk.log)

set -u

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$(cd "$SCRIPT_DIR/../.." && pwd)"
INFO_PLIST="$BUNDLE/Contents/Info"
LOG_FILE="${CLAUDEDESK_LOG:-$HOME/Library/Logs/claudedesk.log}"

log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') [${PROFILE_NAME:-?}] $*"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "$line" >&2
  else
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    echo "$line" >>"$LOG_FILE" 2>/dev/null
  fi
}

plist_read() {
  # $1 = key. Empty output if missing or if `defaults` is unavailable.
  command -v defaults >/dev/null 2>&1 || return 0
  defaults read "$INFO_PLIST" "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------- profile ----
if [[ -n "${CLAUDEDESK_PROFILE_NAME+x}" ]]; then
  PROFILE_NAME="$CLAUDEDESK_PROFILE_NAME"
else
  PROFILE_NAME="$(plist_read ClaudeDeskProfileName)"
fi
PROFILE_NAME="${PROFILE_NAME:-Claude}"

if [[ -n "${CLAUDEDESK_PROFILE_DIR+x}" ]]; then
  PROFILE_DIR_RAW="$CLAUDEDESK_PROFILE_DIR"
else
  PROFILE_DIR_RAW="$(plist_read ClaudeDeskProfileDir)"
fi
# Expand a leading ~ or $HOME. Empty means "Claude's default profile".
PROFILE_DIR="${PROFILE_DIR_RAW/#\~/$HOME}"
PROFILE_DIR="${PROFILE_DIR/#\$HOME/$HOME}"

# ------------------------------------------------------------- UI helpers ----
show_alert() {
  # $1 = title, $2 = message
  log "ALERT: $1 — $2"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  command -v osascript >/dev/null 2>&1 || { echo "$1: $2" >&2; return 0; }
  osascript -e "display alert \"$1\" message \"$2\" as critical" >/dev/null 2>&1 || true
}

ask_first_run() {
  # Prints one of: quit | continue | cancel
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "PROMPT: first sign-in guard (would offer Quit Other Claude / Continue Anyway / Cancel)"
    echo "continue"
    return 0
  fi
  local msg btn
  msg="This looks like the first sign-in for the $PROFILE_NAME profile, and another Claude Desktop window is open."
  msg+=$'\n\n'"Claude finishes sign-in through a claude:// link, and macOS may deliver it to the other window. Quitting the other Claude first makes the sign-in land here."
  btn="$(osascript \
    -e "set r to display dialog \"$msg\" with title \"Claude $PROFILE_NAME\" buttons {\"Cancel\", \"Continue Anyway\", \"Quit Other Claude\"} default button \"Quit Other Claude\" cancel button \"Cancel\"" \
    -e "button returned of r" 2>/dev/null)" || btn="Cancel"
  case "$btn" in
    "Quit Other Claude") echo "quit" ;;
    "Continue Anyway")   echo "continue" ;;
    *)                   echo "cancel" ;;
  esac
}

# --------------------------------------------------------- locate Claude ----
find_claude_app() {
  local c
  for c in "${CLAUDEDESK_CLAUDE_APP:-}" "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
    if [[ -n "$c" && -d "$c" ]]; then echo "$c"; return 0; fi
  done
  if command -v mdfind >/dev/null 2>&1; then
    c="$(mdfind "kMDItemCFBundleIdentifier == 'com.anthropic.claudefordesktop'" 2>/dev/null | head -n 1)"
    if [[ -n "$c" && -d "$c" ]]; then echo "$c"; return 0; fi
  fi
  return 1
}

# ------------------------------------------------- running-instance logic ----
claude_main_pids() {
  # Main Claude processes only. Helper processes live under
  # Contents/Frameworks/… so this pattern excludes them.
  pgrep -f "Claude.app/Contents/MacOS/Claude" 2>/dev/null || true
}

pid_args() {
  ps -o args= -p "$1" 2>/dev/null || true
}

find_instance_pid() {
  # PID of the running instance that belongs to THIS profile, if any.
  local pid args
  for pid in $(claude_main_pids); do
    args="$(pid_args "$pid")"
    [[ -z "$args" ]] && continue
    if [[ -n "$PROFILE_DIR" ]]; then
      if [[ "$args" == *"--user-data-dir=$PROFILE_DIR"* ]]; then echo "$pid"; return 0; fi
    else
      if [[ "$args" != *"--user-data-dir"* ]]; then echo "$pid"; return 0; fi
    fi
  done
  return 1
}

find_other_pids() {
  # PIDs of running instances that belong to OTHER profiles.
  local pid args mine
  mine="$(find_instance_pid || true)"
  for pid in $(claude_main_pids); do
    [[ "$pid" == "$mine" ]] && continue
    args="$(pid_args "$pid")"
    [[ -n "$args" ]] && echo "$pid"
  done
}

activate_pid() {
  log "ACTIVATE pid $1"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $1) to true" >/dev/null 2>&1 || true
}

quit_pids() {
  local pid i
  for pid in "$@"; do
    log "QUIT pid $pid"
    [[ "$DRY_RUN" -eq 1 ]] && continue
    kill -TERM "$pid" 2>/dev/null || true
  done
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  for i in $(seq 1 40); do
    local alive=0
    for pid in "$@"; do kill -0 "$pid" 2>/dev/null && alive=1; done
    [[ "$alive" -eq 0 ]] && return 0
    sleep 0.25
  done
  return 0
}

launch_new() {
  local -a cmd
  cmd=(open -n -a "$CLAUDE_APP")
  if [[ -n "$PROFILE_DIR" ]]; then
    cmd+=(--args "--user-data-dir=$PROFILE_DIR")
  fi
  log "LAUNCH ${cmd[*]}"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  if [[ -n "$PROFILE_DIR" ]]; then mkdir -p "$PROFILE_DIR"; fi
  "${cmd[@]}"
}

# ------------------------------------------------------------------ main ----
CLAUDE_APP="$(find_claude_app || true)"
log "profile_dir=${PROFILE_DIR:-<default>} claude_app=${CLAUDE_APP:-<not found>}"

if [[ -z "$CLAUDE_APP" ]]; then
  show_alert "Claude Desktop not found" "Install Claude Desktop from claude.ai/download into /Applications, then try again."
  exit 1
fi

if existing="$(find_instance_pid)"; then
  activate_pid "$existing"
  exit 0
fi

# First sign-in guard: this profile has never been created, and another
# Claude instance is running. Offer to quit it so the claude:// sign-in
# callback reaches this new window.
if [[ -n "$PROFILE_DIR" && ! -d "$PROFILE_DIR" ]]; then
  others="$(find_other_pids)"
  if [[ -n "$others" ]]; then
    case "$(ask_first_run)" in
      quit)     quit_pids $others ;;
      continue) log "first-run guard: continuing with other instance running" ;;
      cancel)   log "first-run guard: cancelled by user"; exit 0 ;;
    esac
  fi
fi

launch_new
