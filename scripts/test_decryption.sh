#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 6 -strict-concurrency=complete -default-isolation MainActor -parse-as-library \
    "$PROJECT_DIR/ipaDown/Utilities/IPAError.swift" \
    "$PROJECT_DIR/ipaDown/Services/UnfairPlayProcess.swift" \
    "$PROJECT_DIR/ipaDown/Services/DecryptionService.swift" \
    "$PROJECT_DIR/tests/DecryptionServiceTests.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"
