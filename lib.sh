# shellcheck shell=bash
# herdr-spawn — shared helpers (to be sourced).

SPAWN_PLUGIN_ID="herdr-spawn"

plugin_config_dir() {
  if [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ]; then
    printf '%s' "$HERDR_PLUGIN_CONFIG_DIR"
  else
    # Direct CLI invocation (outside plugin context): herdr knows the path.
    "${HERDR_BIN_PATH:-herdr}" plugin config-dir "$SPAWN_PLUGIN_ID" 2>/dev/null
  fi
}

plugin_state_dir() {
  printf '%s' "${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr/plugins/$SPAWN_PLUGIN_ID}"
}

# Load user config over the defaults. The file is seeded from
# config.default on first load — it belongs to the user afterwards
# (herdr never touches the contents of the config dir).
# shellcheck disable=SC2034  # the variables are used by the sourcing scripts
load_config() {
  kind="claude"
  branch_types="feat fix chore docs refactor test perf style ci build"
  branch_type_default="feat"
  focus="false"
  here_direction="right"
  base=""
  history_size=200
  slug_command=""
  slug_warmup=""
  slug_wait=3

  local dir
  dir=$(plugin_config_dir) || return 0
  [ -n "$dir" ] && [ -d "$dir" ] || return 0
  if [ ! -f "$dir/config" ]; then
    cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.default" "$dir/config" 2>/dev/null || true
  fi
  # shellcheck disable=SC1091
  [ -f "$dir/config" ] && . "$dir/config"
  return 0
}

# Inside a plugin popup, HERDR_PANE_ID is absent: the real working pane
# and its cwd come from the invocation context JSON.
context_cwd() {
  [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] || return 1
  jq -r '.focused_pane_cwd // empty' <<<"$HERDR_PLUGIN_CONTEXT_JSON" 2>/dev/null
}

context_pane() {
  [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] || return 1
  jq -r '.focused_pane_id // empty' <<<"$HERDR_PLUGIN_CONTEXT_JSON" 2>/dev/null
}

# ASCII slug of a prompt, truncated to 40 characters.
# python3/unicodedata is locale-independent (iconv transliteration varies
# with LC_CTYPE and truncates on errors); iconv remains as a best-effort
# fallback. A fully non-ASCII prompt yields an empty string.
slugify() {
  local ascii
  if command -v python3 >/dev/null 2>&1; then
    ascii=$(printf '%s' "$1" | python3 -c '
import sys, unicodedata
text = sys.stdin.buffer.read().decode("utf-8", "ignore")
print(unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode(), end="")
' 2>/dev/null) || ascii=""
  else
    # macOS iconv exits non-zero on some characters while still having
    # produced output — hence the || true. Its transliteration artifacts
    # (é → 'e) are stripped.
    ascii=$({ printf '%s' "$1" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || true; } \
      | tr -d "'\`^~\"")
  fi
  # Newlines become spaces first: sed and cut work line by line, and a
  # branch name must be a single line anyway.
  printf '%s' "$ascii" | tr '\n' ' ' | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40
}

# Extract the error code from a herdr CLI JSON response.
# Non-JSON output or a success response yields an empty string.
herdr_error_code() {
  jq -r '.error.code // empty' <<<"$1" 2>/dev/null || true
}

# Conventional-commit type guessed from the prompt's wording (FR/EN
# keywords), used when no LLM names the branch.
guess_type() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    fix*|corrige*|répare*|repare*|debug*|*" bug"*|*crash*|*erreur*|*error*|*broken*|*"ne marche pas"*|*"doesn't work"*) printf 'fix' ;;
    doc*|documente*|*readme*) printf 'docs' ;;
    test*|*"add tests"*|*"ajoute des tests"*|*"écris des tests"*) printf 'test' ;;
    refactor*|réorganise*|reorganise*|nettoie*|renomme*|rename*|*cleanup*|*"clean up"*) printf 'refactor' ;;
    chore*|bump*|upgrade*|*"mets à jour"*|*"met à jour"*|*"update dep"*) printf 'chore' ;;
    perf*|optimise*|optimize*|accélère*|accelere*|*"speed up"*) printf 'perf' ;;
    *) printf '%s' "$branch_type_default" ;;
  esac
}

# Basic conventional branch name: <type>/<slug>. A leading slug word that
# just repeats the type keyword is dropped (fix/fix-login → fix/login).
conventional_branch() {
  local type slug
  type=$(guess_type "$1")
  slug=$(slugify "$1")
  case "$slug" in
    "$type"-?*) slug="${slug#"$type"-}" ;;
  esac
  printf '%s/%s' "$type" "${slug:-task}"
}

# Validate an LLM "type/slug" reply: known type, slugified slug.
# Anything else fails so the caller falls back to conventional_branch.
sanitize_conventional() {
  local raw type slug
  raw=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw" in */*) ;; *) return 1 ;; esac
  type=$(printf '%s' "${raw%%/*}" | sed -E 's/[^a-z]+//g')
  case " $branch_types " in *" $type "*) ;; *) return 1 ;; esac
  slug=$(slugify "${raw#*/}")
  [ -n "$slug" ] || return 1
  printf '%s/%s' "$type" "$slug"
}

# First free branch name: the bare name, then -2, -3, … on collision.
unique_branch() {
  local name="$1" n=2
  if ! git show-ref --verify --quiet "refs/heads/$name"; then
    printf '%s' "$name"
    return 0
  fi
  while git show-ref --verify --quiet "refs/heads/$name-$n"; do n=$((n + 1)); done
  printf '%s-%s' "$name" "$n"
}

# herdr toast (best effort — silent when unavailable).
notify() {
  "${HERDR_BIN_PATH:-herdr}" notification show "$1" --body "${2:-}" --sound none >/dev/null 2>&1 || true
}

# ── LLM-assisted branch slugs (optional, see slug_command in config) ──

# The instruction piped into slug_command, with the task prompt inline.
branch_instruction() {
  printf 'Reply with only a conventional git branch name of the form type/short-kebab-slug, where type is one of: %s. The slug is 2-5 lowercase ascii words. No quotes, no explanations. The coding task:\n\n%s\n' \
    "$(printf '%s' "$branch_types" | tr ' ' ',')" "$1"
}

# Portable timeout (macOS has no coreutils timeout): run "$@" and kill it
# after $1 seconds.
run_with_timeout() {
  local secs=$1 pid watchdog rc
  shift
  "$@" &
  pid=$!
  # The watchdog must not inherit our stdout: a $(…) caller waits for
  # every holder of the pipe, which would stretch fast runs to $secs.
  ( sleep "$secs" && kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" 2>/dev/null
  rc=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return $rc
}

# Synchronous LLM branch name: prompt in, type/slug out (fails on
# timeout or malformed reply). The reply's last non-empty line is used —
# reasoning models may emit thinking noise first.
smart_branch() {
  [ -n "$slug_command" ] || return 1
  local out
  out=$(branch_instruction "$1" \
    | run_with_timeout "${2:-$slug_wait}" bash -c "$slug_command" 2>/dev/null) || true
  out=$(printf '%s\n' "$out" | awk 'NF {line=$0} END {print line}')
  sanitize_conventional "$out"
}
