#!/usr/bin/env python3
"""Dev server for on-device testing.

python -m http.server sends no Cache-Control at all, so Safari is free to reuse
a stale index.html — which during M4a made a fresh build look identical to the
broken one it replaced. This sends no-store on everything, so what a phone loads
is always what was just exported.
"""
import functools
import http.server
import socket


class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        super().end_headers()


def lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


class Server(http.server.ThreadingHTTPServer):
    allow_reuse_address = True   # a quick restart must not hit TIME_WAIT


if __name__ == "__main__":
    port = 8765
    handler = functools.partial(NoCache, directory="dist")
    print(f"  http://{socket.gethostname().split('.')[0]}.local:{port}/?touch=1")
    print(f"  http://{lan_ip()}:{port}/?touch=1")
    Server(("0.0.0.0", port), handler).serve_forever()
