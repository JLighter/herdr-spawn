#!/usr/bin/env bash
#
# herdr-spawn — popup interface (entrypoint "launcher").
#
# Shows the context (project, branch, agent), reads the prompt with
# history (↑/↓), then delegates to spawn.sh.
#   shift+enter — insert a new line (multi-line prompt; needs the kitty
#                 keyboard protocol, which herdr panes speak — otherwise
#                 it falls back to a plain enter)
#   :h          — pick a past prompt with fzf
#   esc         — close the popup when the line is empty; with text, the
#                 line is kept as-is
# Empty line, ctrl+c or ctrl+d: cancel. On error the popup stays open.

set -euo pipefail

root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck disable=SC1091
. "$root/lib.sh"
load_config

# Base ANSI colors: they follow the terminal theme instead of forcing one.
bold=$'\e[1m' dim=$'\e[2m' reset=$'\e[0m'
accent=$'\e[36m' green=$'\e[32m' red=$'\e[31m'

fail_hold() {
  printf '\n%s(press enter to close)%s ' "$dim" "$reset"
  read -r _ || true
}

# ── Keyboard setup ────────────────────────────────────────────────────
# Kitty keyboard protocol (disambiguate flag): makes shift+enter and esc
# reportable as distinct sequences. Terminals without it ignore the
# escape codes and shift+enter degrades to a plain enter.
kitty_push() { printf '\e[>1u'; }
kitty_pop() { printf '\e[<u'; }

# readline macros, loaded via a dedicated INPUTRC (user's inputrc is
# included first so their settings survive):
#   shift+enter (CSI 13;2u)  → insert the ⏎ marker, turned into a real
#                              newline at submission
#   esc (CSI 27u / 27;1u, or a bare \e without kitty) → prefix the line
#                              with a \x01 marker and accept it; the loop
#                              below decides: empty line → close, text →
#                              hand the line back untouched
ESC_MARK=$'\x01'
NL_MARK='⏎'
inputrc_tmp=$(mktemp -t herdr-spawn-inputrc)
{
  user_inputrc="${INPUTRC:-$HOME/.inputrc}"
  [ -f "$user_inputrc" ] && printf '$include %s\n' "$user_inputrc"
  printf '"\\e[13;2u": "%s"\n' "$NL_MARK"
  printf '"\\e[27u": "\\C-a\\C-v\\C-a\\n"\n'
  printf '"\\e[27;1u": "\\C-a\\C-v\\C-a\\n"\n'
  printf '"\\e": "\\C-a\\C-v\\C-a\\n"\n'
  printf 'set keyseq-timeout 200\n'
} > "$inputrc_tmp"
export INPUTRC="$inputrc_tmp"

cleanup_keyboard() {
  kitty_pop
  rm -f "$inputrc_tmp"
}
trap cleanup_keyboard EXIT
kitty_push

# ── Context: project of the pane that was active when the popup opened ──
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
  printf '  %sproject%s  %s%s%s%s\n' "$dim" "$reset" "$bold" "$(basename "$repo_root")" "$reset" \
    "${ws_label:+ $dim(workspace $ws_label)$reset}"
  printf '  %sbranch%s   %s → %s<prompt slug>%s\n' "$dim" "$reset" "${git_branch:-?}" "$dim$branch_prefix" "$reset"
else
  printf '  %sproject%s  %sno git repository — the agent will open as a --here split%s\n' "$dim" "$reset" "$red" "$reset"
fi
printf '  %senter: launch · shift+enter: new line · esc: close · ↑ history · :h fzf%s\n\n' "$dim" "$reset"

# Persistent prompt history (plugin state dir).
state=$(plugin_state_dir)
mkdir -p "$state"
histfile="$state/history"
[ -f "$histfile" ] && history -r "$histfile"

# Input loop: esc and :h prepare the line and hand control back.
prompt=""
initial=""
while :; do
  IFS= read -r -e -i "$initial" -p "  prompt ❯ " entry || exit 0
  initial=""
  case "$entry" in
    "") exit 0 ;;
    "$ESC_MARK") exit 0 ;;
    "$ESC_MARK"*)
      # esc pressed with text on the line: hand it back untouched.
      initial="${entry#"$ESC_MARK"}"
      continue
      ;;
    ":h")
      if ! command -v fzf >/dev/null 2>&1; then
        printf '  %sfzf not found — ↑ walks the history%s\n' "$red" "$reset"
        continue
      fi
      [ -s "$histfile" ] || { printf '  %sempty history%s\n' "$dim" "$reset"; continue; }
      initial=$(fzf --tac --no-sort --height=100% \
        --header='enter: reuse this prompt (editable before launch)' \
        < "$histfile" || true)
      continue
      ;;
    *) prompt="$entry"; break ;;
  esac
done
[ -n "$prompt" ] || exit 0

history -s "$prompt"
history -w "$histfile"
tail -n "${history_size:-200}" "$histfile" > "$histfile.tmp" && mv "$histfile.tmp" "$histfile"

# Turn shift+enter markers into real newlines.
prompt="${prompt//"$NL_MARK"/$'\n'}"

# Branch step (worktree mode only): the generated name, prefilled and
# editable. Enter accepts, empty regenerates the default, esc goes back
# to editing the branch line.
branch=""
if [ -n "$repo_root" ]; then
  default_branch=$(unique_branch "${branch_prefix}$(slugify "$prompt")")
  [ "${default_branch%/}" != "${branch_prefix%/}" ] || default_branch=$(unique_branch "${branch_prefix}task")
  initial="$default_branch"
  while :; do
    IFS= read -r -e -i "$initial" -p "  branch ❯ " entry || exit 0
    case "$entry" in
      "") initial="$default_branch"; continue ;;
      "$ESC_MARK") initial="$default_branch"; continue ;;
      "$ESC_MARK"*) initial="${entry#"$ESC_MARK"}"; continue ;;
      *) branch="$entry"; break ;;
    esac
  done
fi

# Test hook: print the resolved prompt and branch instead of launching.
if [ "${SPAWN_UI_DRY_RUN:-0}" = "1" ]; then
  printf 'DRY_RUN_PROMPT<%s>\n' "$prompt"
  printf 'DRY_RUN_BRANCH<%s>\n' "$branch"
  exit 0
fi

echo
if [ -n "$repo_root" ]; then
  out=$(bash "$root/spawn.sh" -b "$branch" "$prompt" 2>&1) || { printf '  %s✗%s %s\n' "$red" "$reset" "$out"; fail_hold; exit 1; }
else
  # Outside a git repository a worktree is impossible: split instead.
  out=$(bash "$root/spawn.sh" --here "$prompt" 2>&1) || { printf '  %s✗%s %s\n' "$red" "$reset" "$out"; fail_hold; exit 1; }
fi
out="${out#spawn: }"
notify "spawn" "$out"
printf '  %s✓%s %s\n' "$green" "$reset" "$out"
sleep 1.2
