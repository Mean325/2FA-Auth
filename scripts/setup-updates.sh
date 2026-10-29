#!/bin/bash
# Run once on the release maintainer's Mac. Private key material never goes to stdout.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "" && "${1:-}" != "--github" ]]; then
    echo "Usage: $0 [--github]" >&2
    exit 1
fi
xcodebuild -resolvePackageDependencies -project TwoFA.xcodeproj -scheme TwoFA \
    -clonedSourcePackagesDirPath .build/SourcePackages
tools_dir="$PWD/.build/SourcePackages/artifacts/sparkle/Sparkle/bin"
account="app.2famac"
"$tools_dir/generate_keys" --account "$account"
public_key="$("$tools_dir/generate_keys" --account "$account" -p)"
python3 - "$public_key" <<'PY'
import base64
import sys
from pathlib import Path
key = sys.argv[1].strip()
assert len(base64.b64decode(key, validate=True)) == 32, 'Invalid public key'
path = Path('Config/Version.xcconfig')
lines = path.read_text().splitlines()
old = next(line.split('=', 1)[1].strip() for line in lines if line.startswith('SPARKLE_PUBLIC_ED_KEY ='))
assert not old or old == key, 'A different public key is already configured. Do not rotate a released key here.'
path.write_text('\n'.join('SPARKLE_PUBLIC_ED_KEY = ' + key if line.startswith('SPARKLE_PUBLIC_ED_KEY =') else line for line in lines) + '\n')
PY
if [[ "${1:-}" == "--github" ]]; then
    umask 077
    key_dir="$(mktemp -d -t twofa-sparkle-key)"
    key_file="$key_dir/signing.private"
    trap 'rm -f "$key_file"; rmdir "$key_dir"' EXIT
    "$tools_dir/generate_keys" --account "$account" -x "$key_file"
    gh secret set SPARKLE_PRIVATE_KEY --repo Mean325/2FA-Auth < "$key_file"
    echo "Saved SPARKLE_PRIVATE_KEY in GitHub Actions Secrets."
fi
echo "Public key configured. Commit Config/Version.xcconfig and keep the Keychain key backed up."
