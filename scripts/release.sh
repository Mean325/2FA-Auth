#!/bin/bash
# Build and notarize a universal app, then generate an EdDSA-signed Sparkle feed.
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(python3 scripts/release-version.py --check-tag "${1:?Usage: scripts/release.sh v1.0.0}")"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${PROVISIONING_PROFILE_SPECIFIER:?Set PROVISIONING_PROFILE_SPECIFIER}"
: "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID}"
: "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID}"
: "${NOTARY_KEY_PATH:?Set NOTARY_KEY_PATH}"
: "${SPARKLE_PRIVATE_KEY_FILE:?Set SPARKLE_PRIVATE_KEY_FILE}"
out="$PWD/dist/releases/$version"
if [[ -e "$out" ]]; then
    echo "Output already exists: $out. Move it aside before rebuilding." >&2
    exit 1
fi
python3 - <<'PY'
import base64
from pathlib import Path
key = next(line.split('=', 1)[1].strip() for line in Path('Config/Version.xcconfig').read_text().splitlines() if line.startswith('SPARKLE_PUBLIC_ED_KEY ='))
assert len(base64.b64decode(key, validate=True)) == 32, 'Run scripts/setup-updates.sh first.'
PY
mkdir -p "$out" "$out/feed" "$out/dmg-root"
archive="$out/TwoFA.xcarchive"
xcodebuild -project TwoFA.xcodeproj -scheme TwoFA -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -clonedSourcePackagesDirPath .build/SourcePackages \
    -derivedDataPath .build/Release \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY='Developer ID Application' DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    TWOFA_PROVISIONING_PROFILE="$PROVISIONING_PROFILE_SPECIFIER" \
    ENABLE_HARDENED_RUNTIME=YES archive
python3 - "$out/ExportOptions.plist" <<'PY'
import os, plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'method': 'developer-id', 'signingStyle': 'manual',
                  'teamID': os.environ['APPLE_TEAM_ID'], 'signingCertificate': 'Developer ID Application',
                  'provisioningProfiles': {'app.2famac': os.environ['PROVISIONING_PROFILE_SPECIFIER']},
                  'iCloudContainerEnvironment': 'Production'}, f)
PY
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" \
    -exportOptionsPlist "$out/ExportOptions.plist"
app="$out/export/钥记.app"
codesign --verify --deep --strict "$app"
lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/钥记"

# Notarize the app before creating its final, signed update ZIP.
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/notarization.zip"
xcrun notarytool submit "$out/notarization.zip" --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
zip_name="TwoFA-$version-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/feed/$zip_name"
ditto "$app" "$out/dmg-root/钥记.app"
ln -s /Applications "$out/dmg-root/Applications"
dmg="$out/TwoFA-$version-macos-universal.dmg"
hdiutil create -volname "钥记 $version" -srcfolder "$out/dmg-root" -format ULFO "$dmg"
codesign --force --sign 'Developer ID Application' --timestamp "$dmg"
xcrun notarytool submit "$dmg" --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
tools_dir="$PWD/.build/SourcePackages/artifacts/sparkle/Sparkle/bin"
notes="docs/releases/$version.md"
if [[ -f "$notes" ]]; then cp "$notes" "$out/feed/${zip_name%.zip}.md"; fi
"$tools_dir/generate_appcast" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    --download-url-prefix "https://github.com/Mean325/2FA-Auth/releases/download/v$version/" \
    --link "https://github.com/Mean325/2FA-Auth/releases/tag/v$version" \
    --embed-release-notes --maximum-deltas 0 "$out/feed"
cp "$out/feed/$zip_name" "$out/$zip_name"
cp "$out/feed/appcast.xml" "$out/appcast.xml"
python3 scripts/verify-release.py "$out" "$version"
(cd "$out" && shasum -a 256 "$zip_name" "${dmg##*/}" appcast.xml > SHA256SUMS)
echo "Release artifacts ready in $out"
