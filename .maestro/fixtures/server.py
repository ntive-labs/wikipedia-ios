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

# (url substring, fixture file[, extra response headers]) — first match wins.
# ONTHISDAY_FIXTURE selects the On This Day events fixture (e.g. the
# insufficient-events scenario for the WikiGames pairing-fallback flow).
ROUTES = [
    ("onthisday", os.environ.get("ONTHISDAY_FIXTURE", "onthisday_events.json")),
    ("include_text=", "semantic_search_results.json"),
    # Semantic search via MediaWiki full-text search (6240fa0d02, non-el languages):
    # MwQueryResponse with snippet/sectiontitle, plus the x-search-id header the app
    # must thread into its hybrid analytics events.
    ("cirrusSemanticSearch", "semantic_search_results_fulltext.json",
     {"x-search-id": "maestro-search-id-123"}),
    ("feed/configuration", "remote_config.json"),
    ("generator=prefixsearch", "search_results.json"),
    ("list=search", "search_results.json"),
    ("prop=info", "semantic_page_info.json"),
]

# Non-JSON routes: (url substring, fixture file, content type) — first match wins.
# test-pron.mp3 is a real 1s audio file fetched by AVPlayer in the
# pronunciation-user-agent flow (6c43d3fe3c): the -WMFAudioURLHostOverride seam
# redirects the (transcoded …/file.ogg/file.ogg.mp3) pronunciation fetch here,
# and the runner asserts the request's User-Agent from this server's log.
MEDIA_ROUTES = [
    (".mp3", "test-pron.mp3", "audio/mpeg"),
]


class Handler(http.server.BaseHTTPRequestHandler):
    def _log(self, outcome):
        # Includes the request User-Agent: the pronunciation-user-agent runner
        # greps this log to assert media players send the app UA (6c43d3fe3c).
        sys.stderr.write("[fixture] %s %s -> %s UA=%s\n" % (
            self.command, self.path[:120], outcome,
            self.headers.get("User-Agent", "(none)")))

    def _respond(self):
        # Media fixtures (served with their real content type and Range support:
        # AVFoundation probes with Range requests and expects 206es).
        for fragment, fixture, ctype in MEDIA_ROUTES:
            if fragment in self.path:
                with open(os.path.join(FIXTURE_DIR, fixture), "rb") as f:
                    body = f.read()
                self._log(fixture)
                total = len(body)
                range_header = self.headers.get("Range")
                if range_header and range_header.startswith("bytes="):
                    spec = range_header[len("bytes="):].split(",")[0]
                    start_s, _, end_s = spec.partition("-")
                    start = int(start_s) if start_s else 0
                    end = int(end_s) if end_s else total - 1
                    end = min(end, total - 1)
                    chunk = body[start:end + 1]
                    self.send_response(206)
                    self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, total))
                else:
                    chunk = body
                    self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(chunk)))
                self.send_header("Accept-Ranges", "bytes")
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(chunk)
                return
        # Deterministic HTTP failure (client-error-logging flows): any request
        # mentioning this magic term gets a 404, which the app's HTTP layer must
        # report to the mediawiki.client.error logging-intake stream.
        if "errortrigger" in self.path:
            self._log("404")
            body = b"{}"
            self.send_response(404)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        body = b"{}"
        matched = "(default empty)"
        extra_headers = {}
        for route in ROUTES:
            fragment, fixture = route[0], route[1]
            if fragment in self.path:
                fixture_path = os.path.join(FIXTURE_DIR, fixture)
                if os.path.exists(fixture_path):
                    with open(fixture_path, "rb") as f:
                        body = f.read()
                    matched = fixture
                    if len(route) > 2:
                        extra_headers = route[2]
                else:
                    matched = "(missing %s -> default empty)" % fixture
                break
        self._log(matched)
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for name, value in extra_headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    do_GET = _respond
    do_POST = _respond
    do_HEAD = _respond

    def log_message(self, fmt, *args):
        pass  # request logging handled in _respond


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    sys.stderr.write("[fixture] serving on 127.0.0.1:%d (10.0.2.2:%d from emulator)\n" % (PORT, PORT))
    server.serve_forever()
