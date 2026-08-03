# Changelog

## 0.5.0 — 2026-08-03

- **Conventional-commit branch names**: `<type>/<slug>` (feat, fix,
  chore, docs, refactor, test, perf, style, ci, build). The type comes
  from FR/EN keyword heuristics, or from the LLM when `slug_command` is
  set (its reply is validated against `branch_types` and re-slugified).
  Replaces the `branch_prefix` setting.
- The reaper now identifies spawn worktrees through a branch registry in
  the plugin state dir (written at launch, purged on removal) instead of
  a name prefix.
- Fix `run_with_timeout`: the watchdog inherited the caller's stdout and
  stretched every fast LLM call to the full timeout.

## 0.4.0 — 2026-08-03

- **Live branch slug**: the popup is now a two-field editor — the branch
  line refreshes on every keystroke, `tab` jumps to it for manual edits
  (a touched name stops following the prompt; clearing it hands it back).
- **LLM branch names** (optional): `slug_command` pipes the task through
  a (local) model in the background while you type; `slug_warmup`
  preloads the model when the popup opens, `slug_wait` bounds the wait
  at launch. Falls back to the basic slug on timeout or failure.
- Raw-mode keyboard handling (no readline): fixes eaten `esc` and
  phantom reads from canonical-mode windows on macOS, and stops kernel
  echo from bleeding into the rendering.

## 0.3.0 — 2026-08-03

- **Multi-line input removed** (popup `shift+enter` and CLI `--edit`):
  one task, one prompt line. `shift+enter` now submits like a plain
  enter — herdr's encoded sequence is swallowed instead of leaking into
  the line.

## 0.2.1 — 2026-08-03

- Fix `shift+enter` in the popup: bind herdr's default modifyOtherKeys
  encoding (`CSI 27;2;13~`) alongside the kitty form — readline was
  inserting the tail of the unknown sequence into the line.
- Fix GNU mktemp portability (Ubuntu CI).

## 0.2.0 — 2026-08-03

- **Transactional launch**: if the launch fails before the agent has
  started, the created worktree or split is rolled back. A started agent
  is never destroyed.
- **Multi-line prompts**: `shift+enter` inserts a new line in the popup
  (kitty keyboard protocol); `spawn --edit` writes the prompt in
  `$EDITOR` from the CLI.
- **Editable branch name**: the popup prefills the generated name and
  lets you change it before launch.
- **`esc` closes the popup** when the line is empty; with text, the line
  is kept.
- **History picker**: `:h` fuzzy-picks a past prompt with fzf.
- **Reaper**: `spawn done` (and the `herdr-spawn.done` action) lists
  agent worktrees with their state (merged/empty/changes/ahead/live
  agent), fzf multi-select, then removes worktree + branch.
- **Launch toast** through herdr notifications.
- Locale-independent branch slugs (python3/unicodedata, iconv fallback).
- Clean branch names: `-2`, `-3` suffixes only on collision (no more
  timestamps).
- herdr CLI errors matched on exact JSON codes instead of text globs.
- Tests (bats: unit + pty integration via expect), shellcheck CI,
  English translation, bilingual README.

## 0.1.0 — 2026-08-03

- Initial release: launch popup (prompt, history), one git worktree +
  herdr workspace per agent, `--here` opt-out, plugin config file, CLI
  wrapper.
