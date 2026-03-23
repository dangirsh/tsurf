import http.client
import importlib.util
import json
import tempfile
import threading
import unittest
from contextlib import contextmanager
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT_DIR / "extras/scripts/dashboard-server.py"
SPEC = importlib.util.spec_from_file_location("dashboard_server", MODULE_PATH)
dashboard_server = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(dashboard_server)


@contextmanager
def running_server(handler):
    server = dashboard_server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server.server_address[1]
    finally:
        server.shutdown()
        thread.join(timeout=5)
        server.server_close()


class DashboardServerTests(unittest.TestCase):
    def test_collect_units_uses_primary_host_only_and_deduplicates(self):
        manifest = {
            "primary": "dev",
            "hosts": {
                "dev": {
                    "modules": {
                        "networking.nix": [
                            {"systemdUnit": "tailscaled.service"},
                            {"systemdUnit": "sshd.service"},
                            {"systemdUnit": "tailscaled.service"},
                        ]
                    }
                },
                "services": {
                    "modules": {
                        "dashboard.nix": [
                            {"systemdUnit": "nix-dashboard.service"}
                        ]
                    }
                },
            },
        }

        self.assertEqual(
            dashboard_server.collect_units(manifest),
            ["tailscaled.service", "sshd.service"],
        )

    def test_cost_redirect_keeps_security_headers(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            manifest_path = tmp_path / "manifest.json"
            html_path = tmp_path / "dashboard.html"
            manifest_path.write_text(
                json.dumps(
                    {"primary": "dev", "hosts": {"dev": {"modules": {}}}}
                ),
                encoding="utf-8",
            )
            html_path.write_text("<html></html>", encoding="utf-8")

            handler = dashboard_server.make_handler(
                str(manifest_path), str(html_path)
            )
            with running_server(handler) as port:
                conn = http.client.HTTPConnection(
                    "127.0.0.1", port, timeout=5
                )
                conn.request("GET", "/cost")
                response = conn.getresponse()
                response.read()
                conn.close()

            self.assertEqual(response.status, 302)
            self.assertEqual(response.getheader("Location"), "/?tab=cost")
            self.assertEqual(response.getheader("Content-Length"), "0")
            self.assertEqual(
                response.getheader("X-Content-Type-Options"), "nosniff"
            )
            self.assertEqual(response.getheader("X-Frame-Options"), "DENY")
            self.assertEqual(
                response.getheader("Referrer-Policy"), "no-referrer"
            )


if __name__ == "__main__":
    unittest.main()
