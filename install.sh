#!/bin/bash
# Install the "ChatGPT More Details" launcher, a workaround for openai/codex#52483.
# Nothing in /Applications/ChatGPT.app is modified. Re-run to update; ./uninstall.sh to remove.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/ChatGPT.app"
REL="Library/Application Support/codex-more-details"
DIR="$HOME/$REL"
LAUNCHER="$HOME/Applications/ChatGPT More Details.app"
PY=/usr/bin/python3  # launch.sh uses this one, so check it rather than whatever python3 is on PATH

die() { echo "error: $*" >&2; exit 1; }

# ---------------------------------------------------------------- checks
[ "$(uname -s)" = Darwin ] || die "this only works on macOS."
[ "$(id -u)" -ne 0 ] || die "run this as yourself, not with sudo."
[ -f "$APP/Contents/Resources/app.asar" ] || die "ChatGPT isn't installed at $APP."
xcode-select -p >/dev/null 2>&1 && command -v cc >/dev/null \
  || die "the Xcode Command Line Tools are missing. Install them with: xcode-select --install"
"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 6))' 2>/dev/null \
  || die "$PY (3.6 or later) isn't working. It comes with the Xcode Command Line Tools: xcode-select --install"
NODE="$(command -v "${NODE:-node}" || true)"
[ -n "$NODE" ] || die "Node.js not found. Install it (e.g. brew install node), or run with NODE=/path/to/node."
NODE="$(cd "$(dirname "$NODE")" && pwd)/$(basename "$NODE")"
"$NODE" -e 'process.exit(parseInt(process.versions.node) < 18 ? 1 : 0)' \
  || die "Node.js 18 or later is required; $NODE is $("$NODE" --version)."

plist="$APP/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist"))"
echo "ChatGPT $version, Node.js $("$NODE" --version) at $NODE"

# ------------------------------------------------- build in a staging dir
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "Checking that the patch applies (dry run)..."
PATH="$(dirname "$NODE"):$PATH" "$PY" -I "$SRC/more_details_patch.py" --app "$APP" --emit "$STAGE/dry-run" \
  || die "the patch doesn't apply to ChatGPT $version. Nothing was installed."

echo "Compiling spawn_disclaim..."
cc -O2 -o "$STAGE/spawn_disclaim" "$SRC/spawn_disclaim.c" || die "couldn't compile spawn_disclaim.c."

# Fill in launch.sh.in with shell-quoted paths (the support folder has a space in it).
"$PY" -I - "$SRC/launch.sh.in" "$STAGE/launch.sh" "$DIR" "$NODE" <<'EOF'
import shlex, sys
src, dst, d, node = sys.argv[1:]
with open(src) as f:
    text = f.read().replace("@DIR@", shlex.quote(d)).replace("@NODE@", shlex.quote(node))
with open(dst, "w") as f:
    f.write(text)
EOF
bash -n "$STAGE/launch.sh" || die "generated launch.sh has a syntax error."

# ---------------------------------------------------------------- install
# install(1) unlinks each old file first, so a running launcher keeps its copy intact.
mkdir -p "$DIR"
install -m 644 "$SRC/more_details_patch.py" "$SRC/inject.mjs" "$SRC/spawn_disclaim.c" "$DIR/"
install -m 755 "$STAGE/spawn_disclaim" "$STAGE/launch.sh" "$DIR/"
echo "Installed to $DIR"

mkdir -p "$HOME/Applications"
rm -rf "$LAUNCHER"
osacompile -o "$LAUNCHER" -e \
  'do shell script "nohup " & quoted form of (POSIX path of (path to home folder) & "'"$REL"'/launch.sh") & " >/dev/null 2>&1 &"'
echo "Created $LAUNCHER"

echo
echo "Done. Start ChatGPT with \"ChatGPT More Details\" (in ~/Applications, or search for it in Spotlight)."
echo "The first launch of each ChatGPT version takes a few extra seconds to build the patch."
