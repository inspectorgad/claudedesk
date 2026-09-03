#!/bin/bash
# Exercises src/launch.sh in --dry-run mode with fake pgrep/ps, plus a build
# smoke test. Runs on Linux or macOS. No real Claude is touched.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCH="$ROOT/src/launch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_HOME="$TMP/home"
FAKE_APP="$TMP/Claude.app"
mkdir -p "$FAKE_HOME" "$FAKE_APP/Contents/MacOS"
RES_DIR="$FAKE_HOME/Library/Application Support/Claude-Resurrection"

# ---- shims -----------------------------------------------------------------
mkdir -p "$TMP/bin"
PROCS="$TMP/procs.txt"   # lines: PID<TAB>ARGS
cat >"$TMP/bin/pgrep" <<'EOF'
#!/bin/bash
# Only main Claude processes are listed in procs.txt, mirroring what the real
# pattern "Claude.app/Contents/MacOS/Claude" matches.
[[ -s "$PROCS" ]] || exit 1
cut -f1 "$PROCS"
EOF
cat >"$TMP/bin/ps" <<'EOF'
#!/bin/bash
# emulate: ps -o args= -p PID
pid="${4:-}"
awk -F'\t' -v p="$pid" '$1==p {print $2}' "$PROCS"
EOF
chmod +x "$TMP/bin/pgrep" "$TMP/bin/ps"
export PROCS

set_procs() { : >"$PROCS"; for l in "$@"; do printf '%s\n' "$l" >>"$PROCS"; done; }

run_launch() {
  # $1 = profile name, $2 = profile dir (raw, may contain ~)
  HOME="$FAKE_HOME" PATH="$TMP/bin:$PATH" \
  CLAUDEDESK_PROFILE_NAME="$1" CLAUDEDESK_PROFILE_DIR="$2" \
  CLAUDEDESK_CLAUDE_APP="$FAKE_APP" \
  bash "$LAUNCH" --dry-run 2>&1
}

pass=0; fail=0
check() {
  # $1 = test name, $2 = output, $3 = regex that must match, $4 = regex that must NOT match (optional)
  local name="$1" out="$2" must="$3" mustnot="${4:-}"
  if grep -Eq -- "$must" <<<"$out" && { [[ -z "$mustnot" ]] || ! grep -Eq -- "$mustnot" <<<"$out"; }; then
    echo "PASS  $name"; pass=$((pass + 1))
  else
    echo "FAIL  $name"; echo "$out" | sed 's/^/      /'; fail=$((fail + 1))
  fi
}

DEFAULT_ARGS="$FAKE_APP/Contents/MacOS/Claude"
RES_ARGS="$FAKE_APP/Contents/MacOS/Claude --user-data-dir=$RES_DIR"

# ---- cases -----------------------------------------------------------------
set_procs
out="$(run_launch Resurrection '~/Library/Application Support/Claude-Resurrection')"
check "resurrection, nothing running: launches isolated instance, ~ expanded" "$out" \
  "LAUNCH open -n -a $FAKE_APP --args --user-data-dir=$RES_DIR\$" "PROMPT|ACTIVATE"

set_procs
out="$(run_launch SPST '')"
check "spst, nothing running: launches default instance without --args" "$out" \
  "LAUNCH open -n -a $FAKE_APP\$" "user-data-dir|PROMPT|ACTIVATE"

set_procs $'400\t'"$DEFAULT_ARGS" $'501\t'"$RES_ARGS"
out="$(run_launch Resurrection "$RES_DIR")"
check "resurrection already running: activates its pid" "$out" "ACTIVATE pid 501\$" "LAUNCH|PROMPT"

set_procs $'400\t'"$DEFAULT_ARGS" $'501\t'"$RES_ARGS"
out="$(run_launch SPST '')"
check "spst already running alongside resurrection: activates default pid" "$out" "ACTIVATE pid 400\$" "LAUNCH|PROMPT"

set_procs $'501\t'"$RES_ARGS"
out="$(run_launch SPST '')"
check "spst not running, resurrection is: starts a new default instance" "$out" \
  "LAUNCH open -n -a $FAKE_APP\$" "ACTIVATE|PROMPT"

rm -rf "$RES_DIR"
set_procs $'400\t'"$DEFAULT_ARGS"
out="$(run_launch Resurrection "$RES_DIR")"
check "resurrection first run with spst open: shows sign-in guard, then launches" "$out" \
  "PROMPT: first sign-in guard" ""
check "  ...and still launches in dry-run" "$out" "LAUNCH open -n -a $FAKE_APP --args" "ACTIVATE"

mkdir -p "$RES_DIR"
set_procs $'400\t'"$DEFAULT_ARGS"
out="$(run_launch Resurrection "$RES_DIR")"
check "resurrection profile exists, spst open: no guard, launches" "$out" "LAUNCH open -n -a" "PROMPT|ACTIVATE"

set_procs
out="$(HOME="$FAKE_HOME" PATH="$TMP/bin:$PATH" CLAUDEDESK_PROFILE_NAME=X CLAUDEDESK_PROFILE_DIR="" \
       CLAUDEDESK_CLAUDE_APP="$TMP/missing.app" bash "$LAUNCH" --dry-run 2>&1; echo "exit=$?")"
check "claude.app missing: alert and exit 1" "$out" "ALERT: Claude Desktop not found" "LAUNCH"
check "  ...exit code" "$out" "exit=1"

# ---- build smoke test --------------------------------------------------------
BUILD_OUT="$TMP/build"
out="$(CLAUDEDESK_BUILD_DIR="$BUILD_OUT" CLAUDEDESK_CLAUDE_APP="$FAKE_APP" bash "$ROOT/build.sh" 2>&1; echo "exit=$?")"
check "build.sh completes" "$out" "Built 2 launcher\(s\)" "exit=[1-9]"
check "build.sh creates SPST bundle" "$([[ -x "$BUILD_OUT/Claude SPST.app/Contents/MacOS/launch" ]] && echo yes)" "yes"
check "build.sh creates Resurrection bundle" "$([[ -x "$BUILD_OUT/Claude Resurrection.app/Contents/MacOS/launch" ]] && echo yes)" "yes"

plist="$BUILD_OUT/Claude Resurrection.app/Contents/Info.plist"
check "plist has profile dir" "$(cat "$plist")" "<string>~/Library/Application Support/Claude-Resurrection</string>"
check "plist has bundle id" "$(cat "$plist")" "<string>dev.claudedesk.resurrection</string>"
check "plist has display name" "$(cat "$plist")" "<string>Claude Resurrection</string>"
check "plist has no leftover placeholders" "$(cat "$plist"; echo END)" "END" "__[A-Z_]+__"
if command -v python3 >/dev/null 2>&1; then
  out="$(python3 - "$plist" <<'EOF'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    d = plistlib.load(f)
assert d['CFBundleExecutable'] == 'launch'
assert d['LSUIElement'] is True
assert d['ClaudeDeskProfileName'] == 'Resurrection'
print('plist-ok')
EOF
)"
  check "plist parses with plistlib" "$out" "plist-ok"
fi
spst_plist="$BUILD_OUT/Claude SPST.app/Contents/Info.plist"
check "spst plist has empty profile dir" "$(tr -d '\n\t' <"$spst_plist")" "<key>ClaudeDeskProfileDir</key><string></string>"

echo
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
