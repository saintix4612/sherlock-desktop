#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/build/Sherlock Desktop.app/Contents/MacOS/SherlockDesktop"
if [[ ! -x "$APP" ]]; then
  echo "Build first: bash Scripts/build.sh" >&2
  exit 1
fi
command -v python3 >/dev/null
chmod +x "$REPO_ROOT/Tests/sherlock-fixture"
"$APP" --self-test
"$APP" --integration-test "$REPO_ROOT/Tests/sherlock-fixture"
