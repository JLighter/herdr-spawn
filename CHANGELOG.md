# Changelog

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
