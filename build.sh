#!/bin/bash
# build.sh — generate one launcher .app per line of profiles.conf into build/.
#
# Requires only tools that ship with macOS. Runs (minus icons, plist lint and
# signing) on Linux too, which is how the test suite exercises it.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${CLAUDEDESK_BUILD_DIR:-$ROOT/build}"
CONF="${CLAUDEDESK_PROFILES:-$ROOT/profiles.conf}"
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
BUNDLE_ID_PREFIX="dev.claudedesk"

IS_MAC=0
[[ "$(uname -s)" == "Darwin" ]] && IS_MAC=1

info() { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

sed_escape() {
  # Escape a value for use as a sed replacement with '|' as the delimiter.
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//'
}

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

find_source_icon() {
  # Prints the path of Claude.app's .icns, or nothing.
  local app="$1" file
  [[ -z "$app" ]] && return 0
  if command -v defaults >/dev/null 2>&1; then
    file="$(defaults read "$app/Contents/Info" CFBundleIconFile 2>/dev/null || true)"
    [[ -n "$file" && "$file" != *.icns ]] && file="$file.icns"
    [[ -n "$file" && -f "$app/Contents/Resources/$file" ]] && { echo "$app/Contents/Resources/$file"; return 0; }
  fi
  ls "$app"/Contents/Resources/*.icns 2>/dev/null | head -n 1 || true
}

build_icon() {
  # $1 = app bundle, $2 = badge text, $3 = badge color, $4 = source icns (may be empty)
  local app="$1" badge="$2" color="$3" src="$4"
  local dest="$app/Contents/Resources/AppIcon.icns"
  if [[ -z "$src" ]]; then
    warn "Claude.app icon not found; launcher will use the generic app icon"
    return 0
  fi
  if [[ "$IS_MAC" -eq 1 ]] && command -v osascript >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    local iconset
    iconset="$(mktemp -d)/AppIcon.iconset"
    local err
    if err="$(osascript -l JavaScript "$ROOT/src/make-icon.js" "$src" "$badge" "$color" "$iconset" 2>&1 \
             && iconutil -c icns "$iconset" -o "$dest" 2>&1)"; then
      rm -rf "$(dirname "$iconset")"
      info "icon: badged ($badge, #$color)"
      return 0
    fi
    rm -rf "$(dirname "$iconset")"
    warn "badge rendering failed; falling back to the plain Claude icon"
    warn "  $(printf '%s' "$err" | head -n 3 | tr '\n' ' ')"
  fi
  cp "$src" "$dest"
  info "icon: copied from Claude.app"
}

# -------------------------------------------------------------------- main ----
[[ -f "$CONF" ]] || { echo "error: $CONF not found" >&2; exit 1; }
mkdir -p "$OUT"

CLAUDE_APP="$(find_claude_app || true)"
SRC_ICON="$(find_source_icon "$CLAUDE_APP")"
[[ -z "$CLAUDE_APP" ]] && warn "Claude.app not found on this machine (fine for building; needed to launch)"

built=0
seen_default=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(trim "$line")"
  [[ -z "$line" || "$line" == \#* ]] && continue

  IFS='|' read -r name dir badge color <<<"$line"
  name="$(trim "${name:-}")"; dir="$(trim "${dir:-}")"
  badge="$(trim "${badge:-}")"; color="$(trim "${color:-}")"
  [[ -z "$name" ]] && { warn "skipping line without a name: $line"; continue; }
  [[ -z "$badge" ]] && badge="$name"
  [[ -z "$color" ]] && color="1F3A5F"
  if [[ -z "$dir" ]]; then
    if [[ "$seen_default" -eq 1 ]]; then
      warn "more than one profile uses Claude's default data dir; only one should"
    fi
    seen_default=1
  fi

  slug="$(slugify "$name")"
  app_name="Claude $name"
  app="$OUT/$app_name.app"
  echo "Building $app_name.app"

  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

  sed \
    -e "s|__NAME__|$(sed_escape "$app_name")|g" \
    -e "s|__BUNDLE_ID__|$(sed_escape "$BUNDLE_ID_PREFIX.$slug")|g" \
    -e "s|__VERSION__|$(sed_escape "$VERSION")|g" \
    -e "s|__PROFILE_NAME__|$(sed_escape "$name")|g" \
    -e "s|__PROFILE_DIR__|$(sed_escape "$dir")|g" \
    "$ROOT/src/Info.plist.tmpl" >"$app/Contents/Info.plist"

  cp "$ROOT/src/launch.sh" "$app/Contents/MacOS/launch"
  chmod +x "$app/Contents/MacOS/launch"
  printf 'APPL????' >"$app/Contents/PkgInfo"

  build_icon "$app" "$badge" "$color" "$SRC_ICON"

  if command -v plutil >/dev/null 2>&1; then
    plutil -lint -s "$app/Contents/Info.plist"
  fi
  if [[ "$IS_MAC" -eq 1 ]] && command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$app" 2>/dev/null && info "signed: ad hoc"
  fi
  info "profile dir: ${dir:-<Claude default>}"
  built=$((built + 1))
done <"$CONF"

echo
echo "Built $built launcher(s) in $OUT"
