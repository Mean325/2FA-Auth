import contextlib
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_version', Path(__file__).parents[1] / 'release-version.py')
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class ReleaseVersionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name) / 'Version.xcconfig'
        self.config.write_text('MARKETING_VERSION = 1.0.0\nCURRENT_PROJECT_VERSION = $(MARKETING_VERSION)\nSPARKLE_PUBLIC_ED_KEY = test\n')
        config_patch = patch.object(version, 'CONFIG', self.config)
        config_patch.start()
        self.addCleanup(config_patch.stop)

    def invoke(self, *args):
        with patch.object(sys, 'argv', ['release-version.py', *args]), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            version.main()

    def test_accepts_exact_release_tag(self):
        self.invoke('--check-tag', 'v1.0.0')

    def test_rejects_mismatched_and_prerelease_tags(self):
        for tag in ['1.0.0', 'v1.0.1', 'v1.0.0-beta', 'v01.0.0']:
            with self.subTest(tag=tag), self.assertRaises(SystemExit):
                self.invoke('--check-tag', tag)

    def test_bump_preserves_key_and_build_setting(self):
        self.invoke('--set', '1.1.0')
        self.assertEqual(version.current(), '1.1.0')
        self.assertIn('SPARKLE_PUBLIC_ED_KEY = test', self.config.read_text())
        self.assertIn('CURRENT_PROJECT_VERSION = $(MARKETING_VERSION)', self.config.read_text())

    def test_rejects_downgrades_and_noncanonical_versions(self):
        before = self.config.read_text()
        for value in ['1.0.0', '0.9.9', 'v1.1.0', '1.1', '1.01.0', '1.1.0-beta', '1.1.0\n']:
            with self.subTest(value=value), self.assertRaises(SystemExit):
                self.invoke('--set', value)
            self.assertEqual(self.config.read_text(), before)
