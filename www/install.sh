#!/usr/bin/env bash
set -euo pipefail

if ! command -v uv &>/dev/null; then
    echo "Error: uv is not installed."
    echo "Install it from: https://docs.astral.sh/uv/getting-started/installation/"
    exit 1
fi

echo "Installing naaulu..."
uv tool install --python 3.14t "naaulu @ git+https://github.com/naaulu/naaulu.git"

# Wrap the tool to set PYTHON_GIL=0 (needed for free-threaded Python)
TOOL_BIN="$HOME/.local/bin/naaulu"
mv "$TOOL_BIN" "${TOOL_BIN}.python"
cat > "$TOOL_BIN" << 'WRAPPER'
#!/bin/sh
export PYTHON_GIL=0
exec "$(dirname "$0")/naaulu.python" "$@"
WRAPPER
chmod +x "$TOOL_BIN"

echo ""
echo "naaulu installed successfully!"
echo "Run 'naaulu --help' to get started."
