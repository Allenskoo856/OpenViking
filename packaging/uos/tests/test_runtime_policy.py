#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
UOS_DIR = HERE.parent
RUNTIME = UOS_DIR / "runtime"
CONFIG = UOS_DIR / "config" / "ov.conf.example"


def run_python(code: str, **env_overrides):
    env = os.environ.copy()
    env.update(env_overrides)
    env["PYTHONPATH"] = str(RUNTIME)
    return subprocess.run(
        [sys.executable, "-c", code],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


class NetworkPolicyTests(unittest.TestCase):
    def test_offline_allows_loopback_and_blocks_public_dns_before_resolution(self):
        result = run_python(
            "import socket; "
            "socket.getaddrinfo('127.0.0.1', 80); "
            "socket.getaddrinfo('example.com', 443)",
            OPENVIKING_NETWORK_MODE="offline",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("network policy blocked DNS resolution", result.stderr)

    def test_intranet_allows_private_ip_but_requires_hostname_allowlist(self):
        result = run_python(
            "from network_policy import host_is_allowed; "
            "assert host_is_allowed('10.2.3.4'); "
            "assert not host_is_allowed('model.corp.local')",
            OPENVIKING_NETWORK_MODE="intranet",
            OPENVIKING_ALLOWED_HOSTS="",
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_explicit_hostname_is_allowed(self):
        result = run_python(
            "from network_policy import host_is_allowed; "
            "assert host_is_allowed('model.corp.local')",
            OPENVIKING_NETWORK_MODE="intranet",
            OPENVIKING_ALLOWED_HOSTS="model.corp.local",
        )
        self.assertEqual(result.returncode, 0, result.stderr)


class ConfigPolicyTests(unittest.TestCase):
    def _base_env(self):
        return {
            "OPENVIKING_NETWORK_MODE": "intranet",
            "OPENVIKING_ALLOWED_HOSTS": "model.corp.local",
            "OPENVIKING_ROOT_API_KEY": "unit-test-root-api-key-000000000001",
            "OPENVIKING_EMBEDDING_API_BASE": "http://model.corp.local:8000/v1",
            "OPENVIKING_EMBEDDING_API_KEY": "embedding-key",
            "OPENVIKING_EMBEDDING_MODEL": "embedding-model",
            "OPENVIKING_VLM_API_BASE": "http://model.corp.local:8000/v1",
            "OPENVIKING_VLM_API_KEY": "vlm-key",
            "OPENVIKING_VLM_MODEL": "vlm-model",
        }

    def test_example_config_passes_after_environment_is_supplied(self):
        env = os.environ.copy()
        env.update(self._base_env())
        env["PYTHONPATH"] = str(RUNTIME)
        result = subprocess.run(
            [sys.executable, str(RUNTIME / "validate_config.py"), str(CONFIG)],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("configuration accepted", result.stdout)

    def test_public_provider_url_is_rejected(self):
        config = json.loads(
            os.path.expandvars(
                CONFIG.read_text(encoding="utf-8")
                .replace("${OPENVIKING_EMBEDDING_API_BASE}", "https://api.openai.com/v1")
                .replace("${OPENVIKING_EMBEDDING_API_KEY}", "embedding-key")
                .replace("${OPENVIKING_EMBEDDING_MODEL}", "embedding-model")
                .replace("${OPENVIKING_VLM_API_BASE}", "http://10.1.2.3:8000/v1")
                .replace("${OPENVIKING_VLM_API_KEY}", "vlm-key")
                .replace("${OPENVIKING_VLM_MODEL}", "vlm-model")
                .replace("${OPENVIKING_ROOT_API_KEY}", "unit-test-root-api-key-000000000001")
            )
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "ov.conf"
            path.write_text(json.dumps(config), encoding="utf-8")
            env = os.environ.copy()
            env.update(
                OPENVIKING_NETWORK_MODE="intranet",
                OPENVIKING_ALLOWED_HOSTS="",
                PYTHONPATH=str(RUNTIME),
            )
            result = subprocess.run(
                [sys.executable, str(RUNTIME / "validate_config.py"), str(path)],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("api.openai.com", result.stderr)

    def test_rerank_implicit_public_default_is_rejected(self):
        raw = CONFIG.read_text(encoding="utf-8")
        for key, value in self._base_env().items():
            raw = raw.replace("${" + key + "}", value)
        config = json.loads(raw)
        config["rerank"] = {"provider": "cohere", "api_key": "rerank-key"}
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "ov.conf"
            path.write_text(json.dumps(config), encoding="utf-8")
            env = os.environ.copy()
            env.update(
                OPENVIKING_NETWORK_MODE="intranet",
                OPENVIKING_ALLOWED_HOSTS="model.corp.local",
                PYTHONPATH=str(RUNTIME),
            )
            result = subprocess.run(
                [sys.executable, str(RUNTIME / "validate_config.py"), str(path)],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("rerank must declare", result.stderr)


if __name__ == "__main__":
    unittest.main()
