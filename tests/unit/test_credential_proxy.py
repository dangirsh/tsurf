# tests/unit/test_credential_proxy.py
# Unit tests for the root-owned credential proxy (scripts/credential-proxy.py).
# Validates session token auth, upstream key injection, and wrong-token rejection.
import http.client
import importlib.util
import json
import os
import threading
import unittest
from contextlib import contextmanager
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT_DIR / "scripts/credential-proxy.py"
SPEC = importlib.util.spec_from_file_location("credential_proxy", MODULE_PATH)
credential_proxy = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(credential_proxy)


class UpstreamRecorder:
    def __init__(self):
        self.requests = []


def make_upstream_handler(recorder: UpstreamRecorder):
    from http.server import BaseHTTPRequestHandler

    class UpstreamHandler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            return

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length else b""
            recorder.requests.append(
                {
                    "path": self.path,
                    "headers": {k.lower(): v for k, v in self.headers.items()},
                    "body": body,
                }
            )
            response_body = json.dumps({"ok": True}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            self.wfile.write(response_body)

        def do_GET(self):
            recorder.requests.append(
                {
                    "path": self.path,
                    "headers": {k.lower(): v for k, v in self.headers.items()},
                    "body": b"",
                }
            )
            response_body = json.dumps({"ok": True}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            self.wfile.write(response_body)

    return UpstreamHandler


@contextmanager
def running_server(server):
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server.server_address[1]
    finally:
        server.shutdown()
        thread.join(timeout=5)
        server.server_close()


class CredentialProxyTests(unittest.TestCase):
    def setUp(self):
        self.prev_env = os.environ.copy()

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.prev_env)

    def _configure_route(self, service, session_token, real_key):
        os.environ["TSURF_PROXY_ROUTE_COUNT"] = "1"
        os.environ["TSURF_PROXY_ROUTE_0_SERVICE"] = service
        os.environ["TSURF_PROXY_ROUTE_0_SESSION_TOKEN"] = session_token
        os.environ["TSURF_PROXY_ROUTE_0_REAL_KEY"] = real_key

    def test_anthropic_proxy_validates_session_token_and_injects_real_key(self):
        recorder = UpstreamRecorder()
        from http.server import ThreadingHTTPServer

        upstream = ThreadingHTTPServer(
            ("127.0.0.1", 0), make_upstream_handler(recorder)
        )
        with running_server(upstream) as upstream_port:
            self._configure_route("anthropic", "session-token", "real-anthropic-key")
            routes = credential_proxy.load_routes_from_env()
            routes["/anthropic"] = credential_proxy.Route(
                service="anthropic",
                prefix="/anthropic",
                upstream=f"http://127.0.0.1:{upstream_port}",
                session_token="session-token",
                real_key="real-anthropic-key",
            )

            proxy = ThreadingHTTPServer(
                ("127.0.0.1", 0), credential_proxy.make_handler(routes)
            )
            with running_server(proxy) as proxy_port:
                conn = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=5)
                conn.request(
                    "POST",
                    "/anthropic/v1/messages?debug=1",
                    body=b'{"hello":"world"}',
                    headers={
                        "Content-Type": "application/json",
                        "x-api-key": "session-token",
                    },
                )
                response = conn.getresponse()
                response.read()
                conn.close()

        self.assertEqual(response.status, 200)
        self.assertEqual(len(recorder.requests), 1)
        self.assertEqual(recorder.requests[0]["path"], "/v1/messages?debug=1")
        self.assertEqual(
            recorder.requests[0]["headers"]["x-api-key"], "real-anthropic-key"
        )
        self.assertNotIn("session-token", repr(recorder.requests[0]))

    def test_openai_proxy_rejects_wrong_session_token(self):
        recorder = UpstreamRecorder()
        from http.server import ThreadingHTTPServer

        upstream = ThreadingHTTPServer(
            ("127.0.0.1", 0), make_upstream_handler(recorder)
        )
        with running_server(upstream) as upstream_port:
            self._configure_route("openai", "session-token", "real-openai-key")
            routes = credential_proxy.load_routes_from_env()
            routes["/openai"] = credential_proxy.Route(
                service="openai",
                prefix="/openai",
                upstream=f"http://127.0.0.1:{upstream_port}",
                session_token="session-token",
                real_key="real-openai-key",
            )

            proxy = ThreadingHTTPServer(
                ("127.0.0.1", 0), credential_proxy.make_handler(routes)
            )
            with running_server(proxy) as proxy_port:
                conn = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=5)
                conn.request(
                    "GET",
                    "/openai/v1/models",
                    headers={"Authorization": "Bearer wrong-token"},
                )
                response = conn.getresponse()
                response.read()
                conn.close()

        self.assertEqual(response.status, 401)
        self.assertEqual(recorder.requests, [])


if __name__ == "__main__":
    unittest.main()
