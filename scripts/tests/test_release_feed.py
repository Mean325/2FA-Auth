import base64
import importlib.util
import json
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('verify_release', Path(__file__).parents[1] / 'verify-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseFeedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Only throwaway test keys exist here; no access to the maintainer's Keychain.
        result = subprocess.run(['swift', '-e', '''
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
let signature = try key.signature(for: Data("release test archive".utf8))
let data = try JSONSerialization.data(withJSONObject: ["key": key.publicKey.rawRepresentation.base64EncodedString(), "signature": signature.base64EncodedString()])
print(String(data: data, encoding: .utf8)!)
'''], check=True, capture_output=True, text=True)
        cls.keys = json.loads(result.stdout)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.plist = self.root / 'export/钥记.app/Contents/Info.plist'
        self.plist.parent.mkdir(parents=True)
        self.info = {
            'CFBundleIdentifier': 'app.2famac', 'CFBundleShortVersionString': '1.0.0',
            'CFBundleVersion': '1.0.0', 'SUPublicEDKey': self.keys['key'],
            'SUVerifyUpdateBeforeExtraction': True,
            'SUFeedURL': 'https://github.com/Mean325/2FA-Auth/releases/latest/download/appcast.xml',
        }
        self.write_info()
        (self.root / 'TwoFA-1.0.0-macos-universal.zip').write_bytes(b'release test archive')
        (self.root / 'TwoFA-1.0.0-macos-universal.dmg').touch()
        (self.root / 'appcast.xml').write_text(f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:version>1.0.0</sparkle:version><sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
<enclosure url="https://github.com/Mean325/2FA-Auth/releases/download/v1.0.0/TwoFA-1.0.0-macos-universal.zip" length="20" sparkle:edSignature="{self.keys['signature']}"/>
</item></channel></rss>''')

    def write_info(self):
        self.plist.write_bytes(plistlib.dumps(self.info))

    def test_valid_signed_release(self):
        release.verify(self.root, '1.0.0')

    def test_tampered_archive_is_rejected_even_with_matching_length(self):
        (self.root / 'TwoFA-1.0.0-macos-universal.zip').write_bytes(b'RELEASE TEST ARCHIVE')
        with self.assertRaises(subprocess.CalledProcessError):
            release.verify(self.root, '1.0.0')

    def test_wrong_embedded_public_key_is_rejected(self):
        self.info['SUPublicEDKey'] = base64.b64encode(bytes(32)).decode()
        self.write_info()
        with self.assertRaises(subprocess.CalledProcessError):
            release.verify(self.root, '1.0.0')

    def test_mismatched_tag_is_rejected(self):
        with self.assertRaises(AssertionError):
            release.verify(self.root, '1.0.1')

    def test_foreign_download_url_is_rejected(self):
        feed = self.root / 'appcast.xml'
        feed.write_text(feed.read_text().replace('Mean325/2FA-Auth', 'other/repository'))
        with self.assertRaises(AssertionError):
            release.verify(self.root, '1.0.0')
