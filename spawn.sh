#!/usr/bin/env bash
#
# herdr-spawn — engine: launch an agent with a prompt.
#
# By default every agent gets its own git worktree + herdr workspace
# (one agent per branch, isolated from your working directory). --here is
# the explicit opt-out: the agent opens in a split of the current workspace.
#
# Usage:
#   spawn [options] "prompt…"
#   spawn done                   list/clean up agent worktrees
#
#   -H, --here          no worktree: split in the current workspace
#   -k, --kind <kind>   agent to launch (default: config, then claude)
#   -b, --branch <name> branch/worktree name (default: <branch_prefix>
#                       <prompt slug>, suffixed -2, -3… if already taken)
#   -f, --focus         give focus to the agent pane
#
# If the launch fails before the agent has started, the created worktree
# (or split) is removed: no orphaned resources. A started agent is never
# destroyed, even when prompt submission fails.
#
# Defaults (kind, branch_prefix, focus, here_direction, base) come from
# the plugin config: `herdr plugin config-dir herdr-spawn`.
#
# Requires: herdr >= 0.7, jq. Worktree mode runs from a git repository;
# --here runs from a herdr pane (or the plugin popup).

set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$root/lib.sh"
load_config

if [ "${1:-}" = "done" ]; then
  shift
  exec bash "$root/reap.sh" "$@"
fi

here=0
focus_flag=""
branch=""

while [ $# -gt 0 ]; do
  case "$1" in
    -H|--here)   here=1; shift ;;
    -k|--kind)   kind="${2:?spawn: --kind requires a value}"; shift 2 ;;
    -b|--branch) branch="${2:?spawn: --branch requires a value}"; shift 2 ;;
    -f|--focus)  focus_flag="--focus"; shift ;;
    -h|--help)   awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/,""); print}' "$0"; exit 0 ;;
    --)          shift; break ;;
    -*)          echo "spawn: unknown option: $1 (see spawn --help)" >&2; exit 2 ;;
    *)           break ;;
  esac
done

prompt="${*:-}"
[ -n "$prompt" ] || { echo 'usage: spawn [-H] [-k kind] [-b branch] "prompt"' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "spawn: jq is required" >&2; exit 1; }

if [ -z "$focus_flag" ]; then
  case "$focus" in true|1|yes) focus_flag="--focus" ;; *) focus_flag="--no-focus" ;; esac
fi

# Invoked from the plugin popup: move to the active pane's project.
ctx_cwd=$(context_cwd || true)
[ -n "$ctx_cwd" ] && [ -d "$ctx_cwd" ] && cd "$ctx_cwd"

# ── Create the target pane, with rollback until the agent has started ──
# created_ws / created_pane identify the resource to remove on failure;
# agent_started=1 disarms the rollback (never destroy a live agent).
created_ws=""
created_pane=""
agent_started=0

rollback() {
  local code=$?
  [ "$code" -ne 0 ] || return 0
  [ "$agent_started" -eq 0 ] || return 0
  if [ -n "$created_ws" ]; then
    # herdr worktree remove leaves the git branch behind — delete it too,
    # the launch created it.
    "$herdr" worktree remove --workspace "$created_ws" --force >/dev/null 2>&1 \
      && { git branch -D "$branch" >/dev/null 2>&1 || true; \
           echo "spawn: worktree removed (rollback)" >&2; }
  elif [ -n "$created_pane" ]; then
    "$herdr" pane close "$created_pane" >/dev/null 2>&1 \
      && echo "spawn: split closed (rollback)" >&2
  fi
}
trap rollback EXIT

if [ "$here" -eq 1 ]; then
  ctx_pane=$(context_pane || true)
  target_pane="${ctx_pane:-${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}}"
  [ -n "$target_pane" ] \
    || { echo "spawn: --here must run from a herdr pane" >&2; exit 1; }
  pane=$("$herdr" pane split --pane "$target_pane" --direction "$here_direction" "$focus_flag" \
    | jq -re '.result.pane.pane_id')
  created_pane="$pane"
else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "spawn: not inside a git repository — use --here to stay in the workspace" >&2; exit 1; }
  if [ -z "$branch" ]; then
    slug=$(slugify "$prompt")
    branch=$(unique_branch "${branch_prefix}${slug:-task}")
  fi
  base_args=()
  [ -n "$base" ] && base_args=(--base "$base")
  created=$("$herdr" worktree create --cwd "$PWD" --branch "$branch" "${base_args[@]}" "$focus_flag" --json)
  pane=$(jq -re '.result.root_pane.pane_id' <<<"$created")
  created_ws=$(jq -re '.result.workspace.workspace_id' <<<"$created")
fi

# The new pane's shell may still be starting up; agent start then rejects
# with agent_pane_busy — retry until the shell reaches its interactive
# prompt.
started=0
for _ in 1 2 3 4 5 6 7 8; do
  if out=$("$herdr" agent start "$kind" --kind "$kind" --pane "$pane" 2>&1); then
    started=1
    break
  fi
  case "$(herdr_error_code "$out")" in
    agent_pane_busy) sleep 1 ;;
    *) echo "spawn: failed to start $kind: $out" >&2; exit 1 ;;
  esac
done
[ "$started" -eq 1 ] \
  || { echo "spawn: the shell in pane $pane never became available" >&2; exit 1; }
agent_started=1

# Submission right after startup can get lost: the agent is detected
# before its input field accepts input. --wait then fails with
# agent_prompt_stalled (no state change within 5s) — retry. --until
# working returns as soon as the agent starts its turn; a timeout means
# the turn simply ran past 15s (submitted).
submitted=0
for _ in 1 2 3; do
  if out=$("$herdr" agent prompt "$pane" "$prompt" \
    --wait --until working --until blocked --until "done" --timeout 15000 2>&1); then
    submitted=1
    break
  fi
  case "$(herdr_error_code "$out")" in
    agent_prompt_stalled) sleep 1 ;;
    timeout) submitted=1; break ;;
    *) echo "spawn: prompt submission failed: $out" >&2; exit 1 ;;
  esac
done
[ "$submitted" -eq 1 ] \
  || { echo "spawn: the prompt did not take after 3 attempts — pane $pane left open" >&2; exit 1; }

if [ "$here" -eq 1 ]; then
  echo "spawn: $kind launched in the current workspace (pane $pane)"
else
  echo "spawn: $kind launched on branch $branch (pane $pane)"
fi
