#!/usr/bin/env bash
# Builds the isolated environment for the README demo (demo.tape).
# Nothing here touches a real herdr session: spawn.sh is a stub and the
# "LLM" is a sleep + printf.
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
demo="/tmp/herdr-spawn-demo"

rm -rf "$demo"
mkdir -p "$demo/root" "$demo/config" "$demo/state" "$demo/repo"

# The demo repo the popup targets.
git -C "$demo/repo" init -q -b main
git -C "$demo/repo" -c user.name=demo -c user.email=demo@demo \
  commit -q --allow-empty -m init

# Plugin root seen by ui.sh: real UI + helpers, stubbed engine.
ln -s "$plugin_root/ui.sh" "$demo/root/ui.sh"
ln -s "$plugin_root/lib.sh" "$demo/root/lib.sh"
ln -s "$plugin_root/config.default" "$demo/root/config.default"
cat > "$demo/root/spawn.sh" <<'EOF'
#!/usr/bin/env bash
# Demo stub: pretends to create the worktree and launch the agent.
sleep 0.9
echo "spawn: claude launched on branch $2 (pane w3:p1)"
EOF
chmod +x "$demo/root/spawn.sh"

# Demo config: a pretend local LLM that answers after a second.
cat > "$demo/config/config" <<'EOF'
kind=claude
slug_command='sleep 1 && printf "fix/invoice-pagination-crash"'
slug_wait=3
EOF

# Environment sourced by the tape before launching the UI.
cat > "$demo/env.sh" <<EOF
export HERDR_PLUGIN_ROOT="$demo/root"
export HERDR_PLUGIN_CONFIG_DIR="$demo/config"
export HERDR_PLUGIN_STATE_DIR="$demo/state"
export HERDR_PLUGIN_CONTEXT_JSON='{"workspace_label":"api","focused_pane_cwd":"$demo/repo","focused_pane_id":"w1:p1"}'
export HERDR_BIN_PATH=/usr/bin/false
cd "$demo/repo"
EOF

echo "demo env ready: $demo"
