#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT="${1:-8765}"
STREAM_FILE="$SCRIPT_DIR/fa_logging_stream.jsonl"
SERVE="$SCRIPT_DIR/../viewer/serve.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required." >&2
  exit 1
fi

touch "$STREAM_FILE"

exec python3 "$SERVE" \
  --port "$PORT" \
  --stream "$STREAM_FILE" \
  --config "$SCRIPT_DIR"
