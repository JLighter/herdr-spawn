#!/usr/bin/env bash
#
# herdr-spawn — moteur : lance un agent avec un prompt.
#
# Par défaut, chaque agent reçoit son propre worktree git + workspace herdr
# (un agent par branche, isolé du répertoire de travail). --here est
# l'opt-out explicite : l'agent s'ouvre dans un split du workspace courant.
#
# Usage :
#   spawn [options] "prompt…"
#
#   -H, --here          pas de worktree : split dans le workspace courant
#   -k, --kind <kind>   agent à lancer (défaut : config, sinon claude)
#   -b, --branch <nom>  nom de branche/worktree (défaut : <branch_prefix>
#                       <slug du prompt>-<heure>)
#   -f, --focus         donner le focus au pane de l'agent
#
# Les défauts (kind, branch_prefix, focus, here_direction, base) viennent
# de la config du plugin : `herdr plugin config-dir herdr-spawn`.
#
# Requiert : herdr >= 0.7, jq. Le mode worktree se lance depuis un dépôt
# git ; --here depuis un pane herdr (ou le popup du plugin).

set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$root/lib.sh"
load_config

here=0
focus_flag=""
branch=""

while [ $# -gt 0 ]; do
  case "$1" in
    -H|--here)   here=1; shift ;;
    -k|--kind)   kind="${2:?spawn: --kind requiert une valeur}"; shift 2 ;;
    -b|--branch) branch="${2:?spawn: --branch requiert une valeur}"; shift 2 ;;
    -f|--focus)  focus_flag="--focus"; shift ;;
    -h|--help)   awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0 ;;
    --)          shift; break ;;
    -*)          echo "spawn: option inconnue : $1 (voir spawn --help)" >&2; exit 2 ;;
    *)           break ;;
  esac
done

prompt="${*:-}"
[ -n "$prompt" ] || { echo 'usage: spawn [-H] [-k kind] [-b branche] "prompt"' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "spawn: jq est requis" >&2; exit 1; }

if [ -z "$focus_flag" ]; then
  case "$focus" in true|1|yes) focus_flag="--focus" ;; *) focus_flag="--no-focus" ;; esac
fi

# Invoqué par le popup du plugin : se placer dans le projet du pane actif.
ctx_cwd=$(context_cwd || true)
[ -n "$ctx_cwd" ] && [ -d "$ctx_cwd" ] && cd "$ctx_cwd"

if [ "$here" -eq 1 ]; then
  ctx_pane=$(context_pane || true)
  target_pane="${ctx_pane:-${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}}"
  [ -n "$target_pane" ] \
    || { echo "spawn: --here doit être lancé depuis un pane herdr" >&2; exit 1; }
  pane=$("$herdr" pane split --pane "$target_pane" --direction "$here_direction" "$focus_flag" \
    | jq -re '.result.pane.pane_id')
else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "spawn: pas dans un dépôt git — utilise --here pour rester dans le workspace" >&2; exit 1; }
  if [ -z "$branch" ]; then
    # Slug ascii du prompt, tronqué ; l'heure évite les collisions de branche.
    # iconv macOS translittère puis sort en erreur sur certains caractères
    # (« invalid characters ») tout en ayant produit la sortie — d'où le
    # || true. Ses artefacts de translittération (é → 'e) sont supprimés.
    slug=$({ printf '%s' "$prompt" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || true; } \
      | tr -d "'\`^~\"" | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)
    branch="${branch_prefix}${slug:-tache}-$(date +%H%M%S)"
  fi
  base_args=()
  [ -n "$base" ] && base_args=(--base "$base")
  pane=$("$herdr" worktree create --cwd "$PWD" --branch "$branch" "${base_args[@]}" "$focus_flag" --json \
    | jq -re '.result.root_pane.pane_id')
fi

# Le shell du nouveau pane peut être encore en train de démarrer ;
# agent start rejette alors en agent_pane_busy — on réessaie le temps
# que zsh atteigne son prompt interactif.
started=0
for _ in 1 2 3 4 5 6 7 8; do
  out=$("$herdr" agent start "$kind" --kind "$kind" --pane "$pane" 2>&1) && { started=1; break; }
  case "$out" in
    *agent_pane_busy*) sleep 1 ;;
    *) echo "spawn: échec du démarrage de $kind : $out" >&2; exit 1 ;;
  esac
done
[ "$started" -eq 1 ] \
  || { echo "spawn: le shell du pane $pane n'est jamais devenu disponible" >&2; exit 1; }

# La soumission juste après le démarrage peut se perdre : l'agent est
# détecté avant que son champ de saisie n'accepte l'entrée. --wait échoue
# alors en agent_prompt_stalled (aucun changement d'état en 5 s) — on
# réessaie. --until working rend la main dès que l'agent démarre le turn,
# sans attendre sa fin.
submitted=0
for _ in 1 2 3; do
  out=$("$herdr" agent prompt "$pane" "$prompt" \
    --wait --until working --until blocked --until done --timeout 15000 2>&1) && { submitted=1; break; }
  case "$out" in
    *agent_prompt_stalled*) sleep 1 ;;
    *timeout*) submitted=1; break ;;  # soumis, le turn dure juste plus de 15 s
    *) echo "spawn: échec de la soumission du prompt : $out" >&2; exit 1 ;;
  esac
done
[ "$submitted" -eq 1 ] \
  || { echo "spawn: le prompt n'a pas pris après 3 essais — pane $pane laissé ouvert" >&2; exit 1; }

if [ "$here" -eq 1 ]; then
  echo "spawn: $kind lancé dans le workspace courant (pane $pane)"
else
  echo "spawn: $kind lancé sur la branche $branch (pane $pane)"
fi
