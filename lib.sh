# herdr-spawn — helpers partagés entre ui.sh et spawn.sh (à sourcer).

SPAWN_PLUGIN_ID="herdr-spawn"

plugin_config_dir() {
  if [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ]; then
    printf '%s' "$HERDR_PLUGIN_CONFIG_DIR"
  else
    # Appel CLI direct (hors contexte plugin) : herdr fournit le chemin.
    "${HERDR_BIN_PATH:-herdr}" plugin config-dir "$SPAWN_PLUGIN_ID" 2>/dev/null
  fi
}

plugin_state_dir() {
  printf '%s' "${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr/plugins/$SPAWN_PLUGIN_ID}"
}

# Charge la config utilisateur par-dessus les défauts. Le fichier est créé
# depuis config.default au premier chargement — il appartient à l'utilisateur
# ensuite (herdr ne touche jamais au contenu du config dir).
load_config() {
  kind="claude"
  branch_prefix="agent/"
  focus="false"
  here_direction="right"
  base=""
  history_size=200

  local dir
  dir=$(plugin_config_dir) || return 0
  [ -n "$dir" ] && [ -d "$dir" ] || return 0
  if [ ! -f "$dir/config" ]; then
    cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.default" "$dir/config" 2>/dev/null || true
  fi
  # shellcheck disable=SC1091
  [ -f "$dir/config" ] && . "$dir/config"
}

# Dans un popup plugin, HERDR_PANE_ID est absent : le pane de travail réel
# et son cwd viennent du contexte d'invocation JSON.
context_cwd() {
  [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] || return 1
  jq -r '.focused_pane_cwd // empty' <<<"$HERDR_PLUGIN_CONTEXT_JSON" 2>/dev/null
}

context_pane() {
  [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] || return 1
  jq -r '.focused_pane_id // empty' <<<"$HERDR_PLUGIN_CONTEXT_JSON" 2>/dev/null
}
