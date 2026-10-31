#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
# Test a copy with only the class resolver replaced. No Apple session or credentials.
python3 - "$PROJECT_DIR" "$TEST_DIR" <<'PY'
from pathlib import Path
import sys
root, out = map(Path, sys.argv[1:])
s = (root/'ipaDown/Utilities/SAPSigner.m').read_text()
a = s.index('static Class IPACommerceKitSigningSessionClass(')
b = s.index('static NSData *IPACreateSAPSignatureInCurrentPool(', a)
s = s[:a] + 'static Class IPACommerceKitSigningSessionClass(NSError **error) { return NSClassFromString(@"IPATestSigningSession"); }\n\n' + s[b:]
(out/'Signer.m').write_text(s)
PY
xcrun clang -fobjc-arc -fblocks -fsanitize=address -g -O1 -framework Foundation \
    -I "$PROJECT_DIR/ipaDown/Utilities" "$TEST_DIR/Signer.m" \
    "$PROJECT_DIR/tests/SAPSignerLifetimeTests.m" -o "$TEST_DIR/test"
"$TEST_DIR/test"
