# herdr-spawn

Lancer un agent de code avec un prompt, depuis un popup
[herdr](https://herdr.dev) ou en CLI. Par défaut, chaque agent reçoit son
propre worktree git + workspace herdr (un agent par branche, isolé du
répertoire de travail) ; `--here` est l'opt-out explicite.

*English documentation: [README.md](README.md).*

## Installation

```bash
herdr plugin install JLighter/herdr-spawn
```

Ou pour développer en local :

```bash
git clone https://github.com/JLighter/herdr-spawn
herdr plugin link ./herdr-spawn
```

Binding des popups dans `~/.config/herdr/config.toml` :

```toml
[[keys.command]]
key = "prefix+enter"
type = "plugin_action"
command = "herdr-spawn.open"
description = "lancer un agent (worktree + prompt)"

# optionnel : la récolte (spawn done)
[[keys.command]]
key = "prefix+shift+e"
type = "plugin_action"
command = "herdr-spawn.done"
description = "nettoyer les worktrees d'agents"
```

CLI optionnelle : lier `spawn.sh` dans le PATH, p. ex.
`ln -s /path/to/herdr-spawn/spawn.sh ~/.local/bin/spawn`.

## Usage

**Popup** (`prefix+enter`) — affiche le projet et la branche du pane
actif, lit le prompt, puis lance l'agent sans voler le focus :

- `entrée` lance, ligne vide ou `esc` ferme, `ctrl+c`/`ctrl+d` annulent
- `shift+entrée` insère un saut de ligne (prompts multi-lignes ; repose
  sur le protocole clavier kitty, que les panes herdr parlent — sinon
  dégradation en entrée simple)
- `↑` parcourt l'historique persistant des prompts, `:h` y pioche avec fzf
- le nom de branche généré est pré-rempli et **éditable** avant le
  lancement ; vide = défaut régénéré
- hors dépôt git, l'agent s'ouvre en split `--here` au lieu d'un worktree

**CLI** :

```bash
spawn "corrige le bug de pagination"  # worktree + workspace + agent
spawn -e                              # écrire le prompt dans $EDITOR
spawn -H "question rapide"            # split dans le workspace courant
spawn -k opencode -b agent/ma-tache "…"
spawn done                            # lister/nettoyer les worktrees
```

**Récolte** (`spawn done`, ou l'action `herdr-spawn.done`) — liste les
worktrees d'agents du dépôt avec leur état (`[merged]`, `[empty]`,
`[changes]`, `[+N commits]`, `[agent working]`…), sélection multiple
fzf, confirmation, puis retrait worktree + branche. `--list` affiche
l'état seulement.

## Configuration

`herdr plugin config-dir herdr-spawn` imprime le répertoire de config ;
un fichier `config` commenté y est créé au premier lancement : `kind`
(claude/opencode/…), `branch_prefix`, `focus`, `here_direction`, `base`,
`history_size`. Les dimensions des popups se règlent dans
`herdr-plugin.toml` (`[[panes]]`, `width`/`height`).

L'historique des prompts vit dans le state dir du plugin
(`~/.local/state/herdr/plugins/herdr-spawn/history`).

## Notes de robustesse

- Si le lancement échoue avant que l'agent ait démarré, le worktree ou
  le split créé est retiré (rollback) — pas de ressource orpheline. Un
  agent démarré n'est jamais détruit.
- `agent start` est réessayé pendant que le shell du pane démarre
  (`agent_pane_busy`).
- `agent prompt` utilise `--wait` : une soumission perdue au démarrage
  (`agent_prompt_stalled`) est réessayée ; `--until working` rend la
  main dès que l'agent commence son turn.
- Les slugs de branche sont indépendants de la locale
  (python3/unicodedata, repli iconv) et gèrent les collisions (`-2`,
  `-3`, …).

## Requis

herdr ≥ 0.7, `jq`, git. python3 recommandé (slugs sûrs avec accents),
fzf optionnel (picker d'historique, sélection de la récolte). macOS/Linux.

## Développement

```bash
bats tests/        # tests unitaires + intégration pty (requiert expect)
shellcheck -x *.sh
```
