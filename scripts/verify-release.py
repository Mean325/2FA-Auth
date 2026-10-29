#!/usr/bin/env python3
"""Reject an incomplete/mismatched Sparkle feed before uploading a release."""
import base64
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def verify(directory: Path, version: str) -> None:
    with (directory / 'export/钥记.app/Contents/Info.plist').open('rb') as f:
        info = plistlib.load(f)
    assert info['CFBundleIdentifier'] == 'app.2famac', 'Unexpected bundle identifier'
    assert info['CFBundleShortVersionString'] == version, 'App version does not match tag'
    assert info['CFBundleVersion'] == version, 'Build version does not match tag'
    assert len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32, 'Missing public key'
    assert info['SUVerifyUpdateBeforeExtraction'], 'Update verification must be enabled'
    assert info['SUEnableInstallerLauncherService'], 'Sandbox installer service must be enabled'
    assert info['SUFeedURL'] == 'https://github.com/Mean325/2FA-Auth/releases/latest/download/appcast.xml'
    items = ET.parse(directory / 'appcast.xml').findall('./channel/item')
    assert len(items) == 1, 'Expected exactly one release in this feed'
    item = items[0]
    assert item.findtext(SPARKLE + 'version') == version, 'Feed build version mismatch'
    assert item.findtext(SPARKLE + 'shortVersionString') == version, 'Feed version mismatch'
    enclosure = item.find('enclosure')
    assert enclosure is not None, 'Missing download enclosure'
    name = f'TwoFA-{version}-macos-universal.zip'
    assert enclosure.get('url') == f'https://github.com/Mean325/2FA-Auth/releases/download/v{version}/{name}'
    assert int(enclosure.get('length', '0')) == (directory / name).stat().st_size, 'Download length mismatch'
    assert len(base64.b64decode(enclosure.get(SPARKLE + 'edSignature', ''), validate=True)) == 64, 'Missing EdDSA signature'
    assert (directory / f'TwoFA-{version}-macos-universal.dmg').is_file(), 'Missing DMG'
    subprocess.run(['swift', str(Path(__file__).with_name('verify-update.swift')),
                    info['SUPublicEDKey'], enclosure.get(SPARKLE + 'edSignature'), str(directory / name)], check=True)


if __name__ == '__main__':
    verify(Path(sys.argv[1]), sys.argv[2])
    print('App version, feed, signature metadata and artifacts verified.')
