#!/usr/bin/env python3
"""
mock_baccarat_server.py

A minimal local HTTP server that mimics a live baccarat round feed.
Returns a random outcome as JSON on every GET request to /round.

Run:
    python3 mock_baccarat_server.py

Then point Godot's HTTPPoller at:
    http://127.0.0.1:8787/round
"""

import json
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8787

# Weighted like real baccarat odds roughly (player/banker close, tie rarer).
# Adjust these weights freely to stress-test streaks or ties in Godot.
OUTCOME_WEIGHTS = {
    "player": 0.4462,
    "banker": 0.4586,
    "tie": 0.0952,
}


def pick_outcome() -> str:
    outcomes = list(OUTCOME_WEIGHTS.keys())
    weights = list(OUTCOME_WEIGHTS.values())
    return random.choices(outcomes, weights=weights, k=1)[0]


class MockRoundHandler(BaseHTTPRequestHandler):
    # Quiets the default noisy per-request logging; comment out if you
    # want to see every hit from Godot in the console.
    def log_message(self, format, *args):
        pass

    def _send_json(self, status_code: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        # CORS header included in case you ever hit this from a browser-based
        # tool as well; harmless for Godot's HTTPRequest.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/round"):
            outcome = pick_outcome()
            payload = {
                "outcome": outcome,
                "timestamp": time.time(),
            }
            self._send_json(200, payload)
            print(f"[{time.strftime('%H:%M:%S')}] served outcome -> {outcome}")
        else:
            self._send_json(404, {"error": "not found"})

    def do_OPTIONS(self):
        # Not strictly needed for Godot, but harmless to support.
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.end_headers()


def main():
    server = ThreadingHTTPServer((HOST, PORT), MockRoundHandler)
    print(f"Mock baccarat server running at http://{HOST}:{PORT}/round")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()