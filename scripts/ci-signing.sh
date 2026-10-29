#!/bin/bash
# Only used on GitHub's ephemeral macOS runner. Never enable shell tracing here.
set -euo pipefail
: "${SPARKLE_PRIVATE_KEY:?Missing GitHub Actions Secret: SPARKLE_PRIVATE_KEY}"
umask 077
python3 - <<'PY'
import os
from pathlib import Path
path = Path(os.environ['RUNNER_TEMP']) / 'twofa-sparkle.private'
path.write_text(os.environ['SPARKLE_PRIVATE_KEY'].strip() + '\n')
with open(os.environ['GITHUB_ENV'], 'a') as f:
    f.write('SPARKLE_PRIVATE_KEY_FILE=' + str(path) + '\n')
PY
if [[ "${ENABLE_SIGNED_RELEASES:-false}" != true ]]; then
    echo "Using ad-hoc signing. Apple certificate and notarization are optional."
    exit 0
fi
for name in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD APPLE_TEAM_ID \
    NOTARY_KEY_ID NOTARY_ISSUER_ID NOTARY_KEY_BASE64; do
    if [[ -z "${!name:-}" ]]; then
        echo "Missing GitHub Actions Secret: $name" >&2
        exit 1
    fi
done
python3 - <<'PY'
import base64, os
from pathlib import Path
root = Path(os.environ['RUNNER_TEMP'])
for name, filename in [('MACOS_CERTIFICATE_P12_BASE64', 'twofa-certificate.p12'),
                       ('NOTARY_KEY_BASE64', 'twofa-notary.p8')]:
    (root / filename).write_bytes(base64.b64decode(os.environ[name], validate=True))
with open(os.environ['GITHUB_ENV'], 'a') as f:
    for name in ['APPLE_TEAM_ID', 'NOTARY_KEY_ID', 'NOTARY_ISSUER_ID']:
        f.write(name + '=' + os.environ[name] + '\n')
    f.write('NOTARY_KEY_PATH=' + str(root / 'twofa-notary.p8') + '\n')
PY
keychain="$RUNNER_TEMP/twofa-release.keychain-db"
keychain_password="$(openssl rand -base64 32)"
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$RUNNER_TEMP/twofa-certificate.p12" -P "$MACOS_CERTIFICATE_PASSWORD" \
    -k "$keychain" -t cert -f pkcs12 -A
security list-keychains -d user -s "$keychain" login.keychain-db
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain" > /dev/null
