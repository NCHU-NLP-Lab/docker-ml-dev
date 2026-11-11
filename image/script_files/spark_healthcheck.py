#!/usr/bin/env python3
"""Check the development services, without needing a GPU or printing secrets."""
import os
import socket
import urllib.request

with socket.create_connection(("127.0.0.1", int(os.environ.get("SSH_PORT", "22"))), timeout=2) as conn:
    if not conn.recv(255).startswith(b"SSH-"):
        raise SystemExit("No SSH banner")

opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
for variable, default, path in (
    ("JUPYTER_PORT", "8888", "/login"),
    ("VSCODE_PORT", "8080", "/healthz"),
):
    url = "http://127.0.0.1:" + os.environ.get(variable, default) + path
    with opener.open(url, timeout=2) as response:
        if response.status != 200:
            raise SystemExit("Service is not ready: " + variable)
