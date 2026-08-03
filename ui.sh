#!/usr/bin/env bash
#
# herdr-spawn — interface du popup (entrypoint « launcher »).
#
# Affiche le contexte (projet, branche, agent), lit le prompt avec
# historique (↑/↓), puis délègue à spawn.sh. Ligne vide, ctrl+c ou
# ctrl+d : annule. En cas d'erreur, le popup reste ouvert pour lire.

set -euo pipefail

root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck disable=SC1091
. "$root/lib.sh"
load_config

# Couleurs ANSI de base : elles suivent le thème du terminal (Catppuccin
# clair/sombre via Ghostty) au lieu d'imposer une palette.
bold=$'\e[1m' dim=$'\e[2m' reset=$'\e[0m'
accent=$'\e[36m' green=$'\e[32m' red=$'\e[31m'

fail_hold() {
  printf '\n%s(entrée pour fermer)%s ' "$dim" "$reset"
  read -r _ || true
}

# Contexte : projet du pane actif au moment de l'ouverture du popup.
ctx_cwd=$(context_cwd || true)
[ -n "$ctx_cwd" ] && [ -d "$ctx_cwd" ] && cd "$ctx_cwd"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
git_branch=$(git branch --show-current 2>/dev/null || true)
ws_label=""
[ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] \
  && ws_label=$(jq -r '.workspace_label // empty' <<<"$HERDR_PLUGIN_CONTEXT_JSON" 2>/dev/null || true)

printf '\n  %s⚡ spawn%s %s· agent %s%s%s\n' "$bold" "$reset" "$dim" "$reset$accent" "$kind" "$reset"
printf '  %s──────────────────────────────────────────%s\n' "$dim" "$reset"
if [ -n "$repo_root" ]; then
  printf '  %sprojet%s   %s%s%s%s\n' "$dim" "$reset" "$bold" "$(basename "$repo_root")" "$reset" \
    "${ws_label:+ $dim(workspace $ws_label)$reset}"
  printf '  %sbranche%s  %s → %s<slug du prompt>%s\n' "$dim" "$reset" "${git_branch:-?}" "$dim$branch_prefix" "$reset"
else
  printf '  %sprojet%s   %spas de dépôt git — un split --here sera proposé%s\n' "$dim" "$reset" "$red" "$reset"
fi
printf '  %sentrée : lancer · vide ou ctrl+c : annuler · ↑ : historique%s\n\n' "$dim" "$reset"

# Historique persistant des prompts (state dir du plugin).
state=$(plugin_state_dir)
mkdir -p "$state"
histfile="$state/history"
[ -f "$histfile" ] && history -r "$histfile"

IFS= read -r -e -p "  prompt ❯ " prompt || exit 0
[ -n "$prompt" ] || exit 0

history -s "$prompt"
history -w "$histfile"
tail -n "${history_size:-200}" "$histfile" > "$histfile.tmp" && mv "$histfile.tmp" "$histfile"

echo
if [ -n "$repo_root" ]; then
  out=$(bash "$root/spawn.sh" "$prompt" 2>&1) || { printf '  %s✗%s %s\n' "$red" "$reset" "$out"; fail_hold; exit 1; }
else
  # Hors dépôt git, le worktree est impossible : split dans le workspace.
  out=$(bash "$root/spawn.sh" --here "$prompt" 2>&1) || { printf '  %s✗%s %s\n' "$red" "$reset" "$out"; fail_hold; exit 1; }
fi
printf '  %s✓%s %s\n' "$green" "$reset" "${out#spawn: }"
sleep 1.2
