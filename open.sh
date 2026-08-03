#!/usr/bin/env bash
# herdr-spawn — action « open » : ouvre le popup launcher.
# (Bindé sur prefix+enter via type = "plugin_action" dans config.toml.)
set -euo pipefail
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open --plugin herdr-spawn --entrypoint launcher
