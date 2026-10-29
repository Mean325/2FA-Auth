import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / 'ci-signing.sh'


class ReleaseCredentialsTests(unittest.TestCase):
    def run_setup(self, mode=None, key='throwaway-test-key'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = {'PATH': os.environ['PATH'], 'RUNNER_TEMP': directory,
                   'GITHUB_ENV': str(root / 'github-env'), 'SPARKLE_PRIVATE_KEY': key}
            if mode is not None:
                env['ENABLE_SIGNED_RELEASES'] = mode
            result = subprocess.run(['bash', str(SCRIPT)], env=env, text=True, capture_output=True)
            return result, (root / 'github-env').read_text() if (root / 'github-env').exists() else ''

    def test_default_requires_only_sparkle_key(self):
        result, env = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('SPARKLE_PRIVATE_KEY_FILE=', env)
        self.assertNotIn('throwaway-test-key', result.stdout + result.stderr)

    def test_signed_mode_requires_apple_credentials(self):
        result, _ = self.run_setup('true')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('MACOS_CERTIFICATE_P12_BASE64', result.stderr)

    def test_sparkle_key_is_required_even_without_apple_signing(self):
        result, _ = self.run_setup(key='')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SPARKLE_PRIVATE_KEY', result.stderr)
