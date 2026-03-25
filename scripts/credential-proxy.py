#!/usr/bin/env python3
# scripts/credential-proxy.py
# @decision CREDPROXY-145-01: Provider API keys stay in this root-owned process.
#   The agent receives only per-session loopback tokens; killing the proxy invalidates them.

import argparse
import http.client
import os
import urllib.parse
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
}


@dataclass(frozen=True)
class Route:
    service: str
    prefix: str
    upstream: str
    session_token: str
    real_key: str

    @property
    def auth_header(self) -> str:
        if self.service == "anthropic":
            return "x-api-key"
        if self.service == "openai":
            return "authorization"
        raise ValueError(f"unsupported service: {self.service}")

    def validate_incoming_token(self, headers) -> bool:
        if self.service == "anthropic":
            return headers.get("x-api-key") == self.session_token

        auth = headers.get("authorization", "")
        return auth == f"Bearer {self.session_token}"

    def build_upstream_auth(self) -> str:
        if self.service == "anthropic":
            return self.real_key
        if self.service == "openai":
            return f"Bearer {self.real_key}"
        raise ValueError(f"unsupported service: {self.service}")

    def target_url(self, incoming_path: str) -> urllib.parse.SplitResult:
        suffix = incoming_path[len(self.prefix) :]
        if not suffix:
            suffix = "/"
        return urllib.parse.urlsplit(f"{self.upstream}{suffix}")


def route_defaults(service: str) -> tuple[str, str]:
    if service == "anthropic":
        return ("/anthropic", "https://api.anthropic.com")
    if service == "openai":
        return ("/openai", "https://api.openai.com")
    raise ValueError(f"unsupported service: {service}")


def load_routes_from_env() -> dict[str, Route]:
    routes: dict[str, Route] = {}
    count = int(os.environ.get("TSURF_PROXY_ROUTE_COUNT", "0"))
    for idx in range(count):
        service = os.environ[f"TSURF_PROXY_ROUTE_{idx}_SERVICE"]
        session_token = os.environ[f"TSURF_PROXY_ROUTE_{idx}_SESSION_TOKEN"]
        real_key = os.environ[f"TSURF_PROXY_ROUTE_{idx}_REAL_KEY"]
        prefix, upstream = route_defaults(service)
        routes[prefix] = Route(
            service=service,
            prefix=prefix,
            upstream=upstream,
            session_token=session_token,
            real_key=real_key,
        )
    if not routes:
        raise ValueError("no proxy routes configured")
    return routes


def match_route(path: str, routes: dict[str, Route]) -> Route | None:
    for prefix, route in routes.items():
        if path == prefix or path.startswith(f"{prefix}/") or path.startswith(f"{prefix}?"):
            return route
    return None


def make_handler(routes: dict[str, Route]):
    class CredentialProxyHandler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        server_version = "tsurf-credential-proxy/1.0"

        def log_message(self, format: str, *args) -> None:
            return

        def _proxy(self) -> None:
            route = match_route(self.path, routes)
            if route is None:
                self.send_error(404, "unknown credential route")
                return

            if not route.validate_incoming_token(self.headers):
                self.send_error(401, "invalid session token")
                return

            content_length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(content_length) if content_length else None
            target = route.target_url(self.path)

            conn_cls = (
                http.client.HTTPSConnection
                if target.scheme == "https"
                else http.client.HTTPConnection
            )
            connection = conn_cls(target.hostname, target.port, timeout=60)

            upstream_headers = {}
            for key, value in self.headers.items():
                key_lower = key.lower()
                if key_lower in HOP_BY_HOP_HEADERS:
                    continue
                if key_lower == "host":
                    continue
                if key_lower == route.auth_header:
                    continue
                upstream_headers[key] = value

            upstream_headers[route.auth_header] = route.build_upstream_auth()

            path = target.path or "/"
            if target.query:
                path = f"{path}?{target.query}"

            try:
                connection.request(
                    self.command,
                    path,
                    body=body,
                    headers=upstream_headers,
                )
                response = connection.getresponse()
            except OSError as exc:
                self.send_error(502, f"upstream connection failed: {exc}")
                return

            self.send_response(response.status, response.reason)
            for key, value in response.getheaders():
                if key.lower() in HOP_BY_HOP_HEADERS:
                    continue
                self.send_header(key, value)
            self.end_headers()

            while True:
                chunk = response.read(64 * 1024)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()

            connection.close()

        def do_GET(self) -> None:
            self._proxy()

        def do_POST(self) -> None:
            self._proxy()

        def do_PUT(self) -> None:
            self._proxy()

        def do_PATCH(self) -> None:
            self._proxy()

        def do_DELETE(self) -> None:
            self._proxy()

    return CredentialProxyHandler


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Root-owned per-session credential proxy for tsurf agent launches."
    )
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--port-file", required=True)
    args = parser.parse_args()

    routes = load_routes_from_env()
    handler = make_handler(routes)
    server = ThreadingHTTPServer((args.bind, args.port), handler)
    server.daemon_threads = True

    port = server.server_address[1]
    with open(args.port_file, "w", encoding="utf-8") as fh:
        fh.write(f"{port}\n")

    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        return 0
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
