# herdr-spawn

Launch a coding agent with a prompt, from a [herdr](https://herdr.dev)
popup or the CLI. By default every agent gets its own git worktree +
herdr workspace (one agent per branch, isolated from your working
directory); `--here` is the explicit opt-out.

*Documentation en français : [README.fr.md](README.fr.md).*

## Installation

```bash
herdr plugin install JLighter/herdr-spawn
```

Or for local development:

```bash
git clone https://github.com/JLighter/herdr-spawn
herdr plugin link ./herdr-spawn
```

Bind the popups in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+enter"
type = "plugin_action"
command = "herdr-spawn.open"
description = "launch an agent (worktree + prompt)"

# optional: the reaper (spawn done)
[[keys.command]]
key = "prefix+shift+e"
type = "plugin_action"
command = "herdr-spawn.done"
description = "clean up agent worktrees"
```

Optional CLI: link `spawn.sh` into your PATH, e.g.
`ln -s /path/to/herdr-spawn/spawn.sh ~/.local/bin/spawn`.

## Usage

**Popup** (`prefix+enter`) — shows the active pane's project and branch,
reads the prompt, then launches the agent without stealing focus:

- branch names follow the **conventional-commit format** `<type>/<slug>`
  (feat, fix, chore, docs, refactor…) — the type is inferred from the
  prompt wording, or chosen by the LLM with `slug_command`
- the **branch line updates live** while you type the prompt
- `tab` jumps to the branch line to edit the name yourself (it stops
  auto-updating once you touch it; clear it to hand it back)
- `enter` launches (from either field), an empty prompt or `esc` closes,
  `ctrl+c`/`ctrl+d` cancel
- `↑` walks the persistent prompt history, `:h` picks from it with fzf
- outside a git repository the agent opens as a `--here` split instead
  of a worktree

**CLI**:

```bash
spawn "fix the pagination bug"        # worktree + workspace + agent
spawn -H "quick question"             # split in the current workspace
spawn -k opencode -b agent/my-task "…"
spawn done                            # list/clean up agent worktrees
```

**Reaper** (`spawn done`, or the `herdr-spawn.done` action) — lists the
repository's agent worktrees with their state (`[merged]`, `[empty]`,
`[changes]`, `[+N commits]`, `[agent working]`…), fzf multi-select,
confirmation, then removes worktree + branch. `--list` prints the state
only.

## LLM branch names (optional)

Set `slug_command` in the config to name branches with a (local) LLM:
the command receives a ready-made instruction + the task prompt on stdin
and prints a name on stdout (slugified again for safety). In the popup
it runs in the background after a short typing pause — the basic slug
shows until it answers; at launch the popup waits up to `slug_wait`
seconds. `slug_warmup` preloads the model when the popup opens.

```sh
slug_command='ollama run gemma3:4b'
slug_warmup='curl -s http://localhost:11434/api/generate -d "{\"model\":\"gemma3:4b\",\"keep_alive\":\"30m\"}"'
```

## Configuration

`herdr plugin config-dir herdr-spawn` prints the config directory; a
commented `config` file is seeded there on first launch: `kind` (claude/opencode/…), `branch_types`, `branch_type_default`, `focus`, `here_direction`,
`base`, `history_size`, `slug_command`, `slug_warmup`, `slug_wait`. Popup dimensions live in `herdr-plugin.toml`
(`[[panes]]`, `width`/`height`).

Prompt history lives in the plugin state dir
(`~/.local/state/herdr/plugins/herdr-spawn/history`).

## Robustness notes

- If the launch fails before the agent has started, the created worktree
  or split is rolled back — no orphaned resources. A started agent is
  never destroyed.
- `agent start` is retried while the new pane's shell boots
  (`agent_pane_busy`).
- `agent prompt` uses `--wait`: a submission lost at startup
  (`agent_prompt_stalled`) is retried; `--until working` returns as soon
  as the agent begins its turn.
- Branch slugs are locale-independent (python3/unicodedata, iconv
  fallback) and collide gracefully (`-2`, `-3`, …).

## Requirements

herdr ≥ 0.7, `jq`, git. python3 recommended (accent-safe slugs), fzf
optional (history picker, reaper selection). macOS/Linux.

## Development

```bash
bats tests/        # unit + pty integration tests (needs expect)
shellcheck -x *.sh
```
