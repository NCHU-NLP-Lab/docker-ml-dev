"""Run on any host: python3 -m unittest discover -s image/tests -v."""
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


IMAGE_DIR = Path(__file__).resolve().parents[1]
START = IMAGE_DIR / "script_files/spark_start.sh"


class StartupConfigTests(unittest.TestCase):
    def validate(self, **overrides):
        env = {"PATH": os.environ["PATH"], "NAME": "alice", "PASSWORD": "test-only"}
        env.update(overrides)
        return subprocess.run(
            ["bash", str(START), "--check-config"], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )

    def test_legacy_cli_environment(self):
        self.assertEqual(self.validate().returncode, 0)

    def test_custom_identity_and_ports(self):
        result = self.validate(USER_UID="20001", USER_GID="20001", ENABLE_SUDO="0",
                               SSH_PORT="22001", JUPYTER_PORT="22002", VSCODE_PORT="22003")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_configuration(self):
        cases = [
            {"NAME": "root"}, {"NAME": ""}, {"NAME": "alice;id"},
            {"NAME": "../alice"}, {"PASSWORD": ""}, {"PASSWORD": "a\nb"},
            {"PASSWORD": "a\rb"}, {"SSH_PORT": "0"}, {"SSH_PORT": "65536"},
            {"SSH_PORT": "022"}, {"JUPYTER_PORT": "22"}, {"VSCODE_PORT": "8888"},
            {"VSCODE_PORT": "$(id)"}, {"USER_UID": "0"}, {"USER_UID": "999"},
            {"USER_GID": "-1"}, {"USER_GID": "abc"}, {"ENABLE_SUDO": "yes"},
        ]
        for values in cases:
            with self.subTest(values=values):
                self.assertNotEqual(self.validate(**values).returncode, 0)

    def test_secret_is_not_logged_or_evaluated(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "should-not-exist"
            secret = "$(touch '" + str(marker) + "') `id` ; ' \" % : \\ spaces"
            result = self.validate(PASSWORD=secret)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(secret, result.stdout + result.stderr)
            self.assertFalse(marker.exists())

    def test_jupyter_reads_literal_token_from_environment(self):
        config = SimpleNamespace(ServerApp=SimpleNamespace(), IdentityProvider=SimpleNamespace())
        secret = "quotes'\" and $(id) % and spaces"
        with patch.dict(os.environ, {
            "JUPYTER_PORT": "22002", "ML_DEV_HOME": "/user_data", "JUPYTER_TOKEN": secret,
        }):
            runpy.run_path(str(IMAGE_DIR / "config_files/spark_jupyter_config.py"),
                           init_globals={"get_config": lambda: config})
        self.assertEqual(config.IdentityProvider.token, secret)
        self.assertEqual(config.ServerApp.port, 22002)
        self.assertEqual(config.ServerApp.port_retries, 0)
        self.assertEqual(config.ServerApp.root_dir, "/user_data")


if __name__ == "__main__":
    unittest.main()
