#!/usr/bin/env python3
"""Minimal fixture server for Maestro flows.

Serves canned MediaWiki API responses to the app when the app's API base URL
is pointed at this server (http://10.0.2.2:<port> from the emulator's view).

Routing is by URL substring: add an entry to ROUTES mapping a query-string
fragment to a fixture file in this directory. Unmatched API requests get an
empty JSON object, which MediaWiki response models parse as "no results".
"""
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
FIXTURE_DIR = os.path.dirname(os.path.abspath(__file__))

# (url substring, fixture file) — first match wins.
ROUTES = [
    ("onthisday", "onthisday_events.json"),
    ("include_text=", "semantic_search_results.json"),
    ("feed/configuration", "remote_config.json"),
    ("generator=prefixsearch", "search_results.json"),
    ("list=search", "search_results.json"),
    ("prop=info", "semantic_page_info.json"),
]


class Handler(http.server.BaseHTTPRequestHandler):
    def _respond(self):
        body = b"{}"
        matched = "(default empty)"
        for fragment, fixture in ROUTES:
            if fragment in self.path:
                fixture_path = os.path.join(FIXTURE_DIR, fixture)
                if os.path.exists(fixture_path):
                    with open(fixture_path, "rb") as f:
                        body = f.read()
                    matched = fixture
                else:
                    matched = "(missing %s -> default empty)" % fixture
                break
        sys.stderr.write("[fixture] %s %s -> %s\n" % (self.command, self.path[:120], matched))
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = _respond
    do_POST = _respond

    def log_message(self, fmt, *args):
        pass  # request logging handled in _respond


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    sys.stderr.write("[fixture] serving on 127.0.0.1:%d (10.0.2.2:%d from emulator)\n" % (PORT, PORT))
    server.serve_forever()
