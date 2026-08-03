#!/usr/bin/env bash
#
# herdr-spawn — reaper: list and clean up agent worktrees.
#
# Usage:
#   spawn done [--list]
#
# Lists the current repository's worktrees whose branch carries the
# configured prefix (branch_prefix), with their state: merged, empty,
# uncommitted changes, commits ahead, live agent. Multi-select with fzf
# (tab), confirmation, then removal — including the herdr workspace when
# one is open. --list prints the state without offering anything.
#
# Removal deletes the worktree AND its branch. An unmerged branch carries
# a [changes] or [+N commits] tag: your call.

set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$root/lib.sh"
load_config

list_only=0
[ "${1:-}" = "--list" ] && list_only=1

command -v jq >/dev/null 2>&1 || { echo "spawn done: jq is required" >&2; exit 1; }

# Invoked from the plugin popup: move to the active pane's project.
ctx_cwd=$(context_cwd || true)
[ -n "$ctx_cwd" ] && [ -d "$ctx_cwd" ] && cd "$ctx_cwd"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "spawn done: not inside a git repository" >&2; exit 1; }

worktrees=$("$herdr" worktree list --cwd "$PWD" --json 2>&1) \
  || { echo "spawn done: $worktrees" >&2; exit 1; }

# Agents per workspace (to tag worktrees that are still inhabited).
agents=$("$herdr" agent list 2>/dev/null || echo '{}')

# One row per spawn worktree: workspace_id \t branch \t path \t state.
rows=""
while IFS=$'\t' read -r branch path ws_id; do
  [ -n "$branch" ] || continue
  case "$branch" in "$branch_prefix"*) ;; *) continue ;; esac

  tags=""
  if [ -n "$ws_id" ]; then
    status=$(jq -r --arg ws "$ws_id" \
      '[.result.agents[]? | select(.workspace_id == $ws) | .agent_status] | first // empty' <<<"$agents")
    [ -n "$status" ] && tags="${tags}[agent $status] "
  fi
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    tags="${tags}[changes] "
  fi
  ahead=$(git rev-list --count "HEAD..$branch" 2>/dev/null || echo 0)
  if git merge-base --is-ancestor "$branch" HEAD 2>/dev/null; then
    [ -z "$tags" ] && tags="[merged] "
  elif [ "$ahead" -gt 0 ]; then
    tags="${tags}[+$ahead commits] "
  elif [ -z "$tags" ]; then
    tags="[empty] "
  fi

  rows="$rows${ws_id:-∅}"$'\t'"$branch"$'\t'"$path"$'\t'"$tags"$'\n'
done < <(jq -r '.result.worktrees[]? | [.branch // "", .path // "", .open_workspace_id // ""] | @tsv' <<<"$worktrees")

if [ -z "$rows" ]; then
  echo "spawn done: no ${branch_prefix}* worktree in this repository"
  exit 0
fi

display() {
  printf '%s' "$rows" | awk -F'\t' 'NF {printf "  %-34s %s\n", $2, $4}'
}

if [ "$list_only" -eq 1 ] || [ ! -t 0 ]; then
  display
  exit 0
fi

if command -v fzf >/dev/null 2>&1; then
  selected=$(printf '%s' "$rows" | awk -F'\t' 'NF' | fzf -m --tac \
    --delimiter=$'\t' --with-nth=2,4 \
    --header='tab: select · enter: remove selected worktrees · esc: cancel' \
    --height=100%) || exit 0
else
  display
  echo "spawn done: install fzf for interactive selection (--list for the state)"
  exit 0
fi
[ -n "$selected" ] || exit 0

echo "To remove (worktree + branch):"
printf '%s\n' "$selected" | awk -F'\t' '{printf "  %s %s\n", $2, $4}'
printf 'Confirm? [y/N] '
read -r answer
case "$answer" in y|Y) ;; *) echo "cancelled"; exit 0 ;; esac

while IFS=$'\t' read -r ws_id branch path _; do
  [ -n "$branch" ] || continue
  if [ "$ws_id" != "∅" ]; then
    # herdr worktree remove leaves the git branch behind — delete it too.
    "$herdr" worktree remove --workspace "$ws_id" --force >/dev/null 2>&1 \
      && { git branch -D "$branch" >/dev/null 2>&1 || true; \
           echo "removed: $branch (workspace $ws_id)"; continue; }
  fi
  git worktree remove --force "$path" 2>/dev/null || true
  git branch -D "$branch" >/dev/null 2>&1 \
    && echo "removed: $branch" \
    || echo "failed: $branch (remove it manually)" >&2
done <<<"$selected"
