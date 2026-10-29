#!/bin/bash
# Only used on GitHub's ephemeral macOS runner. Never enable shell tracing here.
set -euo pipefail
for name in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_PROVISION_PROFILE_BASE64 \
    APPLE_TEAM_ID NOTARY_KEY_ID NOTARY_ISSUER_ID NOTARY_KEY_BASE64 SPARKLE_PRIVATE_KEY; do
    if [[ -z "${!name:-}" ]]; then
        echo "Missing GitHub Actions Secret: $name" >&2
        exit 1
    fi
done
umask 077
python3 - <<'PY'
import base64, os
from pathlib import Path
root = Path(os.environ['RUNNER_TEMP'])
for name, filename in [('MACOS_CERTIFICATE_P12_BASE64', 'twofa-certificate.p12'),
                       ('MACOS_PROVISION_PROFILE_BASE64', 'twofa-profile.provisionprofile'),
                       ('NOTARY_KEY_BASE64', 'twofa-notary.p8')]:
    (root / filename).write_bytes(base64.b64decode(os.environ[name], validate=True))
(root / 'twofa-sparkle.private').write_text(os.environ['SPARKLE_PRIVATE_KEY'].strip() + '\n')
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
security cms -D -i "$RUNNER_TEMP/twofa-profile.provisionprofile" > "$RUNNER_TEMP/twofa-profile.plist"
python3 - <<'PY'
import datetime, os, plistlib, shutil
from pathlib import Path
root = Path(os.environ['RUNNER_TEMP'])
with (root / 'twofa-profile.plist').open('rb') as f:
    profile = plistlib.load(f)
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Provisioning profile expired'
assert os.environ['APPLE_TEAM_ID'] in profile['TeamIdentifier'], 'Profile team mismatch'
entitlements = profile['Entitlements']
assert entitlements['com.apple.application-identifier'].endswith('.app.2famac'), 'Profile bundle ID mismatch'
assert 'iCloud.app.2famac' in entitlements['com.apple.developer.icloud-container-identifiers'], 'Profile must include the iCloud container'
assert entitlements['com.apple.developer.icloud-container-environment'] == 'Production', 'Use a Developer ID distribution profile'
profile_path = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles' / (profile['UUID'] + '.provisionprofile')
profile_path.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'twofa-profile.provisionprofile', profile_path)
with open(os.environ['GITHUB_ENV'], 'a') as f:
    for name in ['APPLE_TEAM_ID', 'NOTARY_KEY_ID', 'NOTARY_ISSUER_ID']:
        f.write(name + '=' + os.environ[name] + '\n')
    f.write('PROVISIONING_PROFILE_SPECIFIER=' + profile['UUID'] + '\n')
    f.write('PROFILE_PATH=' + str(profile_path) + '\n')
    f.write('NOTARY_KEY_PATH=' + str(root / 'twofa-notary.p8') + '\n')
    f.write('SPARKLE_PRIVATE_KEY_FILE=' + str(root / 'twofa-sparkle.private') + '\n')
(root / 'twofa-profile.plist').unlink()
PY
