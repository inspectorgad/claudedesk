#!/bin/bash
# install.sh — build the launchers and copy them into /Applications
# (or ~/Applications if /Applications is not writable). Safe to re-run.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "install.sh is for macOS. On other systems run ./build.sh to inspect the bundles." >&2
  exit 1
fi

"$ROOT/build.sh"

DEST="/Applications"
if [[ ! -w "$DEST" ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

echo
echo "Installing to $DEST"
installed=()
for app in "$BUILD"/*.app; do
  [[ -d "$app" ]] || continue
  name="$(basename "$app")"
  rm -rf "$DEST/$name"
  cp -R "$app" "$DEST/$name"
  xattr -cr "$DEST/$name" 2>/dev/null || true
  installed+=("$name")
  echo "  $name"
done

# Nudge LaunchServices so Spotlight and Finder pick up the new bundles now.
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREG" ]]; then
  for name in "${installed[@]}"; do "$LSREG" -f "$DEST/$name" >/dev/null 2>&1 || true; done
fi
touch "$DEST" 2>/dev/null || true

cat <<EOF

Done. Next steps:

  1. Open "Claude SPST" (Spotlight or $DEST). It runs your existing
     Claude Desktop profile, already signed in to SPST.

  2. Open "Claude Resurrection". On the first run it offers to quit the
     other Claude window first: accept, then sign in with the Resurrection
     account. Claude finishes sign-in through a claude:// link, and macOS
     may hand that link to whichever Claude window is open, so a lone
     window is the reliable path.

  3. From then on, open either launcher any time. Both instances run side
     by side and stay signed in to their own organization.

  Tip: drag both launchers to the Dock. The running windows both show the
  Claude icon; the launchers are the badged ones.

  The first time a launcher brings a window to the front, macOS asks to let
  it control "System Events". Click OK; that is what focuses the right window.
EOF
