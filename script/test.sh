#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="FilmChefCoreTests"

cd "$ROOT_DIR"

# The test runner is an executable target, not a published product; a full
# build links it with coverage instrumentation without exposing it as a
# release product.
swift build --enable-code-coverage

BUILD_DIR="$(swift build --enable-code-coverage --show-bin-path)"
CODECOV_DIR="$BUILD_DIR/codecov"
TEST_BINARY="$BUILD_DIR/$PRODUCT_NAME"
PROFILE_RAW="$CODECOV_DIR/$PRODUCT_NAME.profraw"
PROFILE_DATA="$CODECOV_DIR/$PRODUCT_NAME.profdata"
COVERAGE_JSON="$CODECOV_DIR/$PRODUCT_NAME.json"

mkdir -p "$CODECOV_DIR"
rm -f "$PROFILE_RAW" "$PROFILE_DATA" "$COVERAGE_JSON"

LLVM_PROFILE_FILE="$PROFILE_RAW" "$TEST_BINARY"

xcrun llvm-profdata merge -sparse "$PROFILE_RAW" -o "$PROFILE_DATA"
xcrun llvm-cov export "$TEST_BINARY" \
  -instr-profile="$PROFILE_DATA" \
  -format=text \
  "$ROOT_DIR/Sources/FilmChefCore" \
  > "$COVERAGE_JSON"

echo
echo "Coverage report: $COVERAGE_JSON"
xcrun llvm-cov report "$TEST_BINARY" \
  -instr-profile="$PROFILE_DATA" \
  "$ROOT_DIR/Sources/FilmChefCore"
