#!/bin/bash
# uninstall.sh — remove the launcher apps. Claude Desktop itself and its
# default profile are never touched.
#
#   ./uninstall.sh                  remove the launchers only
#   ./uninstall.sh --purge-profiles also delete the extra profile data dirs
#                                   listed in profiles.conf (asks first)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONF="${CLAUDEDESK_PROFILES:-$ROOT/profiles.conf}"
PURGE=0
[[ "${1:-}" == "--purge-profiles" ]] && PURGE=1

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

removed=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(trim "$line")"
  [[ -z "$line" || "$line" == \#* ]] && continue
  IFS='|' read -r name dir _ <<<"$line"
  name="$(trim "${name:-}")"; dir="$(trim "${dir:-}")"
  [[ -z "$name" ]] && continue

  for base in "/Applications" "$HOME/Applications"; do
    app="$base/Claude $name.app"
    if [[ -d "$app" ]]; then
      rm -rf "$app"
      echo "Removed $app"
      removed=$((removed + 1))
    fi
  done

  if [[ "$PURGE" -eq 1 && -n "$dir" ]]; then
    dir="${dir/#\~/$HOME}"
    dir="${dir/#\$HOME/$HOME}"
    if [[ -d "$dir" ]]; then
      printf 'Delete profile data for %s at %s? This signs that instance out for good. [y/N] ' "$name" "$dir"
      read -r answer
      if [[ "$answer" == [yY]* ]]; then
        rm -rf "$dir"
        echo "Deleted $dir"
      else
        echo "Kept $dir"
      fi
    fi
  fi
done <"$CONF"

rm -rf "$ROOT/build"
echo "Removed $removed launcher(s). Claude Desktop and its default profile were left alone."
