import importlib.util
import time
import unittest
from pathlib import Path
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("oauth_broker_app", Path(__file__).with_name("app.py"))
APP = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(APP)


class OAuthBrokerTests(unittest.TestCase):
    def test_protected_resource_metadata_url_with_path(self):
        self.assertEqual(
            APP.metadata_url("https://example.com/mcp"),
            "https://example.com/.well-known/oauth-protected-resource/mcp",
        )

    def test_authorization_metadata_url_with_issuer_path(self):
        self.assertEqual(
            APP.authorization_metadata_url("https://auth.example.com/tenant"),
            "https://auth.example.com/.well-known/oauth-authorization-server/tenant",
        )

    def test_resource_metadata_header(self):
        self.assertEqual(
            APP.parse_resource_metadata_header(
                'Bearer realm="mcp", resource_metadata="https://example.com/oauth-resource"'
            ),
            "https://example.com/oauth-resource",
        )

    def test_status_is_redacted(self):
        record = {
            "token": {
                "access_token": "do-not-return",
                "refresh_token": "do-not-return",
                "expires_at": time.time() + 300,
                "scope": "docs.read",
            },
            "discovery": {"issuer": "https://auth.example.com"},
        }
        with patch.object(APP, "server_config", return_value={"authentication": {"type": "oauth"}}):
            with patch.object(APP, "load_store", return_value={"docs": record}):
                value = APP.status("docs")
        self.assertTrue(value["connected"])
        self.assertTrue(value["refreshable"])
        self.assertNotIn("access_token", str(value))
        self.assertNotIn("refresh_token", str(value))
        self.assertNotIn("do-not-return", str(value))

    def test_access_token_returns_only_short_lived_token(self):
        record = {
            "token": {
                "access_token": "access",
                "refresh_token": "refresh",
                "token_type": "Bearer",
                "expires_at": time.time() + 300,
            }
        }
        with patch.object(APP, "server_config", return_value={"authentication": {"type": "oauth"}}):
            with patch.object(APP, "load_store", return_value={"docs": record}):
                value = APP.access_token("docs")
        self.assertEqual(value["accessToken"], "access")
        self.assertNotIn("refresh", str(value))


if __name__ == "__main__":
    unittest.main()
