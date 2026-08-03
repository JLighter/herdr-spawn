#!/usr/bin/env bash
#
# herdr-spawn — popup interface (entrypoint "launcher").
#
# The branch name lives in the header and refreshes live while you type
# the prompt below it.
#   enter  — launch (from either field)
#   tab    — jump to the branch line and edit the name yourself (it stops
#            auto-updating once you type in it; empty = auto again)
#   ctrl+g — name the branch with slug_command (LLM), on demand
#   esc    — close when the prompt is empty; from the branch line, jump
#            back to the prompt
#   ↑/↓    — walk the persistent prompt history
#   :h     — as the whole prompt + enter: pick a past prompt with fzf
# ctrl+c / ctrl+d cancel. On error the popup stays open.
#
# No readline here: keys are read raw so the branch line can refresh on
# every keystroke, and herdr's encodings (shift+enter as CSI 27;2;13~ or
# CSI 13;2u, esc as CSI 27u) are handled explicitly.

set -euo pipefail

root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck disable=SC1091
. "$root/lib.sh"
load_config

bold=$'\e[1m' dim=$'\e[2m' reset=$'\e[0m'
accent=$'\e[36m' green=$'\e[32m' red=$'\e[31m'

# Raw mode for the whole input session. Toggling per-read (what plain
# `read -n1` does) bounces the tty between canonical and raw mode, and
# characters arriving in a canonical window get eaten or surface as
# phantom empty reads (observed on macOS with a bare esc). -echo also
# stops the kernel from echoing keystrokes over our own rendering.
stty_saved=$(stty -g 2>/dev/null || true)
restore_tty() {
  [ -n "$stty_saved" ] || return 0
  stty "$stty_saved" 2>/dev/null || true
}
cleanup_ui() {
  restore_tty
  type stop_slug_job >/dev/null 2>&1 && stop_slug_job
}
trap cleanup_ui EXIT
trap 'exit 0' INT
stty -echo -icanon min 1 time 0 2>/dev/null || true

fail_hold() {
  printf '\n%s(press enter to close)%s ' "$dim" "$reset"
  read -r _ || true
}

# Preload the slug model (fire-and-forget) so slug_command answers fast
# when ctrl+g asks for a name.
[ -n "$slug_warmup" ] && ( bash -c "$slug_warmup" >/dev/null 2>&1 & )

# ── Context: project of the pane that was active when the popup opened ──
ctx_cwd=$(context_cwd || true)
[ -n "$ctx_cwd" ] && [ -d "$ctx_cwd" ] && cd "$ctx_cwd"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
git_branch=$(git branch --show-current 2>/dev/null || true)
ws_label=""
[ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] \
  && ws_label=$(jq -r '.workspace_label // empty' <<<"$HERDR_PLUGIN_CONTEXT_JSON" 2>/dev/null || true)

# ── Prompt history ────────────────────────────────────────────────────
state=$(plugin_state_dir)
mkdir -p "$state"
histfile="$state/history"
hist=()
[ -f "$histfile" ] && mapfile -t hist < "$histfile"
hist_idx=${#hist[@]}
hist_stash=""

# ── Editor state ──────────────────────────────────────────────────────
prompt_text=""
branch_text=""
branch_auto=1
focus="prompt"        # prompt | branch
cur_p=0               # cursor offset in the prompt field
cur_b=0               # cursor offset in the branch field
cursor_on_branch=0    # is the physical cursor parked on the branch line?

default_branch() {
  unique_branch "$(conventional_branch "$prompt_text")"
}

refresh_branch() {
  [ "$branch_auto" -eq 1 ] || return 0
  if [ -n "$repo_root" ] && [ -n "$prompt_text" ]; then
    branch_text=$(default_branch)
  else
    branch_text=""
  fi
  cur_b=${#branch_text}
}

# ── LLM naming job (slug_command), started on demand with ctrl+g ──────
slug_job_pid=""
slug_job_file=""
slug_job_prompt=""

stop_slug_job() {
  [ -n "$slug_job_pid" ] && kill "$slug_job_pid" 2>/dev/null
  wait "$slug_job_pid" 2>/dev/null || true
  [ -n "$slug_job_file" ] && rm -f "$slug_job_file"
  slug_job_pid="" slug_job_file=""
}

start_slug_job() {
  [ -n "$slug_command" ] && [ -n "$repo_root" ] && [ -n "$prompt_text" ] || return 0
  stop_slug_job
  slug_job_prompt="$prompt_text"
  slug_job_file=$(mktemp "${TMPDIR:-/tmp}/herdr-spawn-slug.XXXXXX")
  ( branch_instruction "$prompt_text" | bash -c "$slug_command" > "$slug_job_file" 2>/dev/null ) &
  slug_job_pid=$!
}

# Collect a finished job. Returns 0 when the branch line changed.
poll_slug_job() {
  [ -n "$slug_job_pid" ] || return 1
  kill -0 "$slug_job_pid" 2>/dev/null && return 1
  local out name
  out=$(awk 'NF {line=$0} END {print line}' "$slug_job_file" 2>/dev/null)
  rm -f "$slug_job_file"
  slug_job_pid="" slug_job_file=""
  [ "$branch_auto" -eq 1 ] || return 1
  [ "$slug_job_prompt" = "$prompt_text" ] || return 1
  name=$(sanitize_conventional "$out") || return 1
  branch_text=$(unique_branch "$name")
  cur_b=${#branch_text}
  return 0
}

# ── Rendering ─────────────────────────────────────────────────────────
# Layout: the branch line belongs to the header, BRANCH_OFFSET rows above
# the prompt line (help line and a blank line sit between them).
BRANCH_OFFSET=3

draw_header() {
  printf '\n  %s⚡ spawn%s %s· agent %s%s%s\n' "$bold" "$reset" "$dim" "$reset$accent" "$kind" "$reset"
  printf '  %s──────────────────────────────────────────%s\n' "$dim" "$reset"
  if [ -n "$repo_root" ]; then
    printf '  %sproject%s  %s%s%s%s%s\n' "$dim" "$reset" "$bold" "$(basename "$repo_root")" "$reset" \
      "${ws_label:+ ${dim}(workspace $ws_label)$reset}" "${git_branch:+ ${dim}· base $git_branch$reset}"
  else
    printf '  %sproject%s  %sno git repository — the agent will open as a --here split%s\n' "$dim" "$reset" "$red" "$reset"
  fi
  printf '\n'   # branch line, filled in by draw_fields
  if [ -n "$slug_command" ]; then
    printf '  %senter: launch · tab: branch · ctrl+g: ai name · esc: close · ↑ hist · :h fzf%s\n' "$dim" "$reset"
  else
    printf '  %senter: launch · tab: edit branch · esc: close · ↑ history · :h fzf%s\n' "$dim" "$reset"
  fi
  printf '\n'   # blank line; the cursor now sits on the prompt line
}

# One field line: label, text windowed around the cursor, and the
# terminal column where the cursor belongs.
FIELD_COL=11  # columns before the text: "  <label> ❯ "
render_field() { # $1=label $2=text $3=cursor $4=style
  local text="$2" cur="$3" avail start visible
  avail=$(( ${COLUMNS:-$(tput cols 2>/dev/null || echo 80)} - FIELD_COL - 2 ))
  start=0
  [ "$cur" -ge "$avail" ] && start=$((cur - avail + 1))
  visible="${text:start:avail}"
  printf '\r\e[K  %s%s ❯%s %s%s%s' "$dim" "$1" "$reset" "$4" "$visible" "$reset"
  RENDER_CURSOR_COL=$((FIELD_COL + cur - start))
}

draw_fields() {
  local branch_style="$dim" branch_shown="$branch_text"
  [ "$focus" = "branch" ] && branch_style="$reset"
  if [ -z "$repo_root" ]; then
    branch_shown="(--here split, no worktree)"
  elif [ -n "$slug_job_pid" ] && [ "$branch_auto" -eq 1 ]; then
    branch_shown="$branch_text ⋯"
  fi
  # Return to the prompt-line anchor, then paint both lines.
  [ "$cursor_on_branch" -eq 1 ] && printf '\e[%dB' "$BRANCH_OFFSET"
  printf '\e[%dA' "$BRANCH_OFFSET"
  render_field "branch" "$branch_shown" "$cur_b" "$branch_style"
  local col_b=$RENDER_CURSOR_COL
  printf '\e[%dB' "$BRANCH_OFFSET"
  render_field "prompt" "$prompt_text" "$cur_p" "$reset"
  local col_p=$RENDER_CURSOR_COL
  if [ "$focus" = "branch" ]; then
    printf '\e[%dA\r' "$BRANCH_OFFSET"
    [ "$col_b" -gt 0 ] && printf '\e[%dC' "$col_b"
    cursor_on_branch=1
  else
    printf '\r'
    [ "$col_p" -gt 0 ] && printf '\e[%dC' "$col_p"
    cursor_on_branch=0
  fi
}

# ── Key reading: assemble escape sequences ────────────────────────────
KEY=""
PENDING_KEY=""
read_key() {
  local ch seq rc
  if [ -n "$PENDING_KEY" ]; then
    KEY="$PENDING_KEY"
    PENDING_KEY=""
    return 0
  fi
  # Timed first read so the loop gets periodic ticks (slug job polling).
  IFS= read -rsn1 -t 0.25 ch
  rc=$?
  if [ "$rc" -gt 128 ]; then
    KEY="TICK"
    return 0
  fi
  [ "$rc" -eq 0 ] || return 1
  # read -n1 strips its newline delimiter: an empty read IS an enter.
  if [ -z "$ch" ]; then
    KEY=$'\n'
    return 0
  fi
  if [ "$ch" != $'\e' ]; then
    KEY="$ch"
    return 0
  fi
  if ! IFS= read -rsn1 -t 0.05 ch; then
    KEY="ESC"
    return 0
  fi
  if [ "$ch" = '[' ] || [ "$ch" = 'O' ]; then
    seq=""
    while IFS= read -rsn1 -t 0.05 ch; do
      seq+="$ch"
      case "$ch" in [A-Za-z~]) break ;; esac
    done
    KEY="CSI:$seq"
  else
    # A key typed right behind a bare esc landed in the lookahead window
    # (slow redraws widen it): treat it as esc + that key, not alt+key.
    KEY="ESC"
    [ -z "$ch" ] && ch=$'\n'
    PENDING_KEY="$ch"
  fi
}

field_insert() { # $1=char
  if [ "$focus" = "prompt" ]; then
    prompt_text="${prompt_text:0:cur_p}$1${prompt_text:cur_p}"
    cur_p=$((cur_p + 1))
    refresh_branch
  elif [ -n "$repo_root" ]; then
    branch_text="${branch_text:0:cur_b}$1${branch_text:cur_b}"
    cur_b=$((cur_b + 1))
    branch_auto=0
  fi
}

field_backspace() {
  if [ "$focus" = "prompt" ]; then
    [ "$cur_p" -gt 0 ] || return 0
    prompt_text="${prompt_text:0:cur_p-1}${prompt_text:cur_p}"
    cur_p=$((cur_p - 1))
    refresh_branch
  else
    [ "$cur_b" -gt 0 ] || return 0
    branch_text="${branch_text:0:cur_b-1}${branch_text:cur_b}"
    cur_b=$((cur_b - 1))
    branch_auto=0
  fi
}

field_kill_line() {
  if [ "$focus" = "prompt" ]; then
    prompt_text="" cur_p=0
    refresh_branch
  else
    # Stays empty while editing; auto mode resumes when leaving the field.
    branch_text="" cur_b=0
    branch_auto=0
  fi
}

# An emptied branch field hands the name back to the generator once the
# focus leaves it (regenerating live would fight the user's typing).
leave_branch_field() {
  focus="prompt"
  [ -n "$branch_text" ] || { branch_auto=1; refresh_branch; }
}

history_move() { # $1=-1|1
  [ "$focus" = "prompt" ] || return 0
  [ "${#hist[@]}" -gt 0 ] || return 0
  local next=$((hist_idx + $1))
  { [ "$next" -lt 0 ] || [ "$next" -gt "${#hist[@]}" ]; } && return 0
  [ "$hist_idx" -eq "${#hist[@]}" ] && hist_stash="$prompt_text"
  hist_idx=$next
  if [ "$hist_idx" -eq "${#hist[@]}" ]; then
    prompt_text="$hist_stash"
  else
    prompt_text="${hist[hist_idx]}"
  fi
  cur_p=${#prompt_text}
  refresh_branch
}

pick_history_fzf() {
  command -v fzf >/dev/null 2>&1 || return 0
  [ -s "$histfile" ] || return 0
  local pick
  pick=$(fzf --tac --no-sort --height=100% \
    --header='enter: reuse this prompt (editable before launch)' \
    < "$histfile" || true)
  clear
  draw_header
  cursor_on_branch=0
  [ -n "$pick" ] && { prompt_text="$pick"; cur_p=${#prompt_text}; }
  refresh_branch
}

# At launch time, give a ctrl+g job still in flight a bounded chance to
# land: the branch line keeps refreshing while we wait.
await_slug_job() {
  [ -n "$slug_job_pid" ] || return 0
  [ "${slug_wait:-3}" -gt 0 ] 2>/dev/null || { stop_slug_job; return 0; }
  local deadline=$(( ${slug_wait:-3} * 4 )) i=0
  while [ -n "$slug_job_pid" ] && [ "$i" -lt "$deadline" ]; do
    if poll_slug_job; then draw_fields; return 0; fi
    sleep 0.25
    i=$((i + 1))
  done
  poll_slug_job && draw_fields
  stop_slug_job
  return 0
}

# ── Main loop ─────────────────────────────────────────────────────────
draw_header
draw_fields

while read_key; do
  if [ "$KEY" = "TICK" ]; then
    poll_slug_job && draw_fields
    continue
  fi
  case "$KEY" in
    $'\r'|$'\n'|"CSI:27;2;13~"|"CSI:13;2u")
      if [ "$prompt_text" = ":h" ]; then
        prompt_text="" cur_p=0
        pick_history_fzf
        draw_fields
        continue
      fi
      [ -n "$prompt_text" ] || exit 0
      await_slug_job
      break
      ;;
    "ESC"|"CSI:27u"|"CSI:27;1u")
      if [ "$focus" = "branch" ]; then
        leave_branch_field
      elif [ -z "$prompt_text" ]; then
        exit 0
      fi
      ;;
    $'\t')
      if [ -n "$repo_root" ]; then
        if [ "$focus" = "prompt" ]; then focus="branch"; else leave_branch_field; fi
      fi
      ;;
    $'\x07')
      # ctrl+g: name the branch with slug_command, on demand.
      if [ -n "$slug_command" ] && [ -n "$repo_root" ] && [ -n "$prompt_text" ]; then
        branch_auto=1
        start_slug_job
      fi
      ;;
    $'\x7f'|$'\x08') field_backspace ;;
    $'\x15') field_kill_line ;;
    $'\x04') exit 0 ;;
    $'\x01') if [ "$focus" = "prompt" ]; then cur_p=0; else cur_b=0; fi ;;
    $'\x05') if [ "$focus" = "prompt" ]; then cur_p=${#prompt_text}; else cur_b=${#branch_text}; fi ;;
    "CSI:A") history_move -1 ;;
    "CSI:B") history_move 1 ;;
    "CSI:D") if [ "$focus" = "prompt" ]; then [ "$cur_p" -gt 0 ] && cur_p=$((cur_p - 1)); else [ "$cur_b" -gt 0 ] && cur_b=$((cur_b - 1)); fi ;;
    "CSI:C") if [ "$focus" = "prompt" ]; then [ "$cur_p" -lt "${#prompt_text}" ] && cur_p=$((cur_p + 1)); else [ "$cur_b" -lt "${#branch_text}" ] && cur_b=$((cur_b + 1)); fi ;;
    "CSI:H"|"CSI:1~") if [ "$focus" = "prompt" ]; then cur_p=0; else cur_b=0; fi ;;
    "CSI:F"|"CSI:4~") if [ "$focus" = "prompt" ]; then cur_p=${#prompt_text}; else cur_b=${#branch_text}; fi ;;
    CSI:*|META:*) : ;;   # unknown sequences are swallowed, never inserted
    *)
      case "$KEY" in
        [[:print:]]) field_insert "$KEY" ;;
      esac
      ;;
  esac
  # Batch redraws: skip when more input is already queued (fast typing).
  if ! IFS= read -rsn0 -t 0 2>/dev/null; then
    draw_fields
  fi
done

# Move below the prompt line before printing anything else.
[ "$cursor_on_branch" -eq 1 ] && printf '\e[%dB' "$BRANCH_OFFSET"
printf '\n'

[ -n "$prompt_text" ] || exit 0
[ -n "$branch_text" ] || { [ -n "$repo_root" ] && branch_text=$(default_branch); }

printf '%s\n' "$prompt_text" >> "$histfile"
tail -n "${history_size:-200}" "$histfile" > "$histfile.tmp" && mv "$histfile.tmp" "$histfile"

# Test hook: print the resolved prompt and branch instead of launching.
if [ "${SPAWN_UI_DRY_RUN:-0}" = "1" ]; then
  printf 'DRY_RUN_PROMPT<%s>\n' "$prompt_text"
  printf 'DRY_RUN_BRANCH<%s>\n' "$branch_text"
  exit 0
fi

echo
if [ -n "$repo_root" ]; then
  out=$(bash "$root/spawn.sh" -b "$branch_text" "$prompt_text" 2>&1) \
    || { printf '  %s✗%s %s\n' "$red" "$reset" "$out"; fail_hold; exit 1; }
else
  # Outside a git repository a worktree is impossible: split instead.
  out=$(bash "$root/spawn.sh" --here "$prompt_text" 2>&1) \
    || { printf '  %s✗%s %s\n' "$red" "$reset" "$out"; fail_hold; exit 1; }
fi
out="${out#spawn: }"
notify "spawn" "$out"
printf '  %s✓%s %s\n' "$green" "$reset" "$out"
sleep 1.2
