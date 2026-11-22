#!/bin/bash
# Moldable — Little Wishes, Big River · serve this folder locally (double-click in Finder).
cd "$(dirname "$0")" || exit 1
PORT=4173
echo "→ http://localhost:$PORT  (Ctrl+C to stop)"
( sleep 1; open "http://localhost:$PORT" ) &
exec python3 -m http.server "$PORT"
