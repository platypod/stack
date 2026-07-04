#!/bin/sh
# Point Claude Code (terminal CLI *and* the Desktop app) at the Headroom
# proxy by writing ANTHROPIC_BASE_URL into ~/.claude/settings.json's `env`
# block — the same mechanism already used there for the OTEL vars.
#
# A shell `export` doesn't work for this: Claude Desktop is a GUI app and
# doesn't inherit your terminal's environment, and even the terminal `claude`
# only re-reads env vars at process start. settings.json is read on launch
# regardless of how the process was started, so it's the one mechanism that
# reaches both. Existing keys (env.OTEL_*, hooks, theme, ...) are preserved.
#
# Usage:
#   bin/set-claude-proxy.sh on <base-url>   # e.g. https://headroom.platypod.local
#   bin/set-claude-proxy.sh off

set -e

info() { printf '\033[1;33m[info]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[0;32m[ok]\033[0m     %s\n' "$*"; }
die()  { printf '\033[0;31m[error]\033[0m  %s\n' "$*" >&2; exit 1; }

command -v jq > /dev/null 2>&1 || die "jq is required — brew install jq"

MODE="$1"
BASE_URL="$2"
SETTINGS="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"

case "$MODE" in
  on)
    [ -n "$BASE_URL" ] || die "Usage: $0 on <base-url>"
    ;;
  off) ;;
  *)
    die "Usage: $0 on <base-url> | $0 off"
    ;;
esac

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [ "$MODE" = "on" ]; then
  jq --arg url "$BASE_URL" '.env.ANTHROPIC_BASE_URL = $url' "$SETTINGS" > "$TMP"
else
  jq 'if .env then .env |= del(.ANTHROPIC_BASE_URL) else . end' "$SETTINGS" > "$TMP"
fi

mv "$TMP" "$SETTINGS"

if [ "$MODE" = "on" ]; then
  ok "Set env.ANTHROPIC_BASE_URL = $BASE_URL in $SETTINGS"
else
  ok "Removed env.ANTHROPIC_BASE_URL from $SETTINGS"
fi
info "Restart Claude Code (quit + relaunch, terminal or Desktop) for this to take effect."
