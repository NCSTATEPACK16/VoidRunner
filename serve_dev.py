#!/usr/bin/env python3
"""Dev server for on-device testing, over HTTPS.

Godot 4 web requires a *secure context*. Browsers grant that to http://localhost
automatically, which is why desktop testing always worked — but a phone reaching
this machine by LAN name or IP over plain HTTP does not qualify, and the engine
refuses to start with "Secure Context - Check web server configuration". Hence a
self-signed certificate: it is the whole reason on-device testing was impossible.

python -m http.server sends no Cache-Control at all, so Safari is free to reuse
a stale index.html — which during M4a made a fresh build look identical to the
broken one it replaced. This sends no-store on everything, so what a phone loads
is always what was just exported.
"""
import functools
import http.server
import pathlib
import socket
import ssl


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
    httpd = Server(("0.0.0.0", port), handler)

    certs = pathlib.Path(__file__).parent / ".certs"
    crt, key = certs / "dev.crt", certs / "dev.key"
    scheme = "http"
    if crt.exists() and key.exists():
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(certfile=crt, keyfile=key)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
        scheme = "https"
    else:
        print("  !! no .certs/dev.crt — serving plain HTTP; Godot will refuse to")
        print("     start on any device that is not localhost (secure context)")

    host = socket.gethostname().split(".")[0]
    print(f"  {scheme}://{host}.local:{port}/")
    print(f"  {scheme}://{lan_ip()}:{port}/")
    httpd.serve_forever()
