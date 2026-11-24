#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/27anims-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
test_sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -fobjc-arc -Wall -Wextra -Werror -isysroot "$test_sdk" \
    -framework Foundation -framework CoreGraphics tests/compatibility.m -o "$test_dir/compatibility"
"$test_dir/compatibility"
