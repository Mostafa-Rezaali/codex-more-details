#!/bin/bash
# Remove the "ChatGPT More Details" launcher and its support folder.
# ChatGPT itself was never modified, so there is nothing else to undo.
set -eu

DIR="$HOME/Library/Application Support/codex-more-details"
LAUNCHER="$HOME/Applications/ChatGPT More Details.app"

for p in "$LAUNCHER" "$DIR"; do
  if [ -e "$p" ]; then rm -rf "$p"; echo "Removed $p"; else echo "Not found: $p"; fi
done

if pgrep -f "codex-more-details/inject.mjs" >/dev/null; then
  echo "ChatGPT is still running with the patch. Quit it, and it opens normally from then on."
fi
