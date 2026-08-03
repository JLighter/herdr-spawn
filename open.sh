#!/usr/bin/env bash
# herdr-spawn — opens a plugin popup: launcher (default) or reaper.
# (Bound via type = "plugin_action" in config.toml, e.g. prefix+enter.)
set -euo pipefail
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open --plugin herdr-spawn --entrypoint "${1:-launcher}"
