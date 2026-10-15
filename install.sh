#!/usr/bin/env bash
# Points Claude Code's statusLine setting at this repo's statusline.sh.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
COMMAND="sh $SCRIPT"

for dep in jq curl; do
    if ! command -v "$dep" > /dev/null; then
        echo "ERROR: $dep is required but not installed" >&2
        exit 1
    fi
done

mkdir -p "$(dirname "$SETTINGS")"

if [[ -f "$SETTINGS" ]]; then
    current=$(jq -r '.statusLine.command // empty' "$SETTINGS")
    if [[ "$current" == "$COMMAND" ]]; then
        echo "Already installed: $COMMAND"
        exit 0
    fi
    [[ -n "$current" ]] && echo "Replacing existing statusLine: $current"

    cp "$SETTINGS" "$SETTINGS.bak"
    echo "Backed up $SETTINGS to $SETTINGS.bak"
    jq --arg cmd "$COMMAND" '.statusLine = {type: "command", command: $cmd}' "$SETTINGS.bak" > "$SETTINGS"
else
    jq -n --arg cmd "$COMMAND" '{statusLine: {type: "command", command: $cmd}}' > "$SETTINGS"
fi

echo "Installed: $COMMAND"
echo "Start a new Claude Code session to see it."
