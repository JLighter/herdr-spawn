# herdr-spawn

Lancer un agent de code avec un prompt, depuis un popup
[herdr](https://herdr.dev) ou en CLI. Par défaut, chaque agent reçoit son
propre worktree git + workspace herdr (un agent par branche, isolé du
répertoire de travail) ; `--here` est l'opt-out explicite.

## Installation

```bash
herdr plugin install JLighter/herdr-spawn
```

Ou pour développer en local :

```bash
git clone https://github.com/JLighter/herdr-spawn
herdr plugin link ./herdr-spawn
```

Binding du popup dans `~/.config/herdr/config.toml` :

```toml
[[keys.command]]
key = "prefix+enter"
type = "plugin_action"
command = "herdr-spawn.open"
description = "lancer un agent (worktree + prompt)"
```

CLI optionnelle : ajouter un lien vers `spawn.sh` dans le PATH, p. ex.
`ln -s /path/to/herdr-spawn/spawn.sh ~/.local/bin/spawn`.

## Usage

- **Popup** (`prefix+enter`) : affiche le projet et la branche du pane
  actif, lit le prompt (↑ = historique), lance l'agent sans voler le
  focus. Ligne vide, ctrl+c ou ctrl+d annule. Hors dépôt git, l'agent
  s'ouvre en split `--here` au lieu d'un worktree.
- **CLI** : `spawn "corrige le bug X"` — options `-H/--here`, `-k kind`,
  `-b branche`, `-f/--focus` (voir `spawn --help`).

## Configuration

`herdr plugin config-dir herdr-spawn` imprime le répertoire de config ;
le fichier `config` y est créé au premier lancement (copie commentée de
`config.default`) : `kind`, `branch_prefix`, `focus`, `here_direction`,
`base`, `history_size`. Les dimensions du popup se règlent dans
`herdr-plugin.toml` (`[[panes]]`, `width`/`height`).

L'historique des prompts vit dans le state dir du plugin
(`~/.local/state/herdr/plugins/herdr-spawn/history`).

## Notes de robustesse

- `agent start` est réessayé tant que le shell du nouveau pane démarre
  (`agent_pane_busy`).
- `agent prompt` utilise `--wait` : une soumission perdue au démarrage
  (`agent_prompt_stalled`) est réessayée ; `--until working` rend la main
  dès que l'agent commence son turn.

## Requis

herdr ≥ 0.7, `jq`, git. macOS/Linux.
