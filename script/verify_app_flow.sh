#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FilmChef"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"

cd "$ROOT_DIR"

cleanup() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

./script/test.sh
swift build
./script/build_and_run.sh --verify

[[ -d "$APP_BUNDLE" ]] || {
  echo "missing staged app bundle: $APP_BUNDLE" >&2
  exit 1
}

pgrep -x "$APP_NAME" >/dev/null || {
  echo "$APP_NAME did not remain running after app-flow verification" >&2
  exit 1
}

echo "App-flow smoke verification passed for $APP_BUNDLE"
