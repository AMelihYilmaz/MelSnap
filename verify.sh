#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir=$(mktemp -d)
swiftc -D MELSNAP_TEST -parse-as-library -module-cache-path "${MELSNAP_SWIFT_CACHE:-$test_dir/cache}" \
    MelSnap.swift Tests/Verify05.swift -o "$test_dir/verify"
"$test_dir/verify" "$test_dir/data"
