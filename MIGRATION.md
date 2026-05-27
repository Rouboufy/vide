# 🔀 Migration — Nmux42 → Vide

> Ce document trace la feuille de route de la migration depuis Nmux42 vers Vide. Il recense ce qui est **porté tel quel**, ce qui doit être **adapté**, et ce qui est **abandonné** — ainsi que les raisons de chaque décision.

---

## 🗺️ Vue d'ensemble

| Composant | Statut | Effort |
|-----------|--------|--------|
| Script d'installation (`setup.sh`) | 🔄 Adapté | Moyen |
| Script de désinstallation (`uninstall.sh`) | 🔄 Adapté | Faible |
| Script de mise à jour (`update.sh`) | ✅ Porté | Faible |
| Config Neovim (`nvim/`) | 🔄 Adapté | Élevé |
| Config Tmux (`tmux.conf`) | ❌ Abandonné | — |
| Sync thème Tmux (`tmux-theme.sh`) | 🔄 Adapté → WezTerm | Moyen |
| Gestion des keybindings | 🔄 Adapté | Élevé |
| Japonette TUI | ✅ Porté | Faible |
| Dashboard Neovim | ✅ Porté | Faible |
| Logique 42 Network (SSL, sudo-free) | ✅ Porté | Faible |

---

## ✅ Porté tel quel

Ces éléments fonctionnent déjà bien dans Nmux42 et n'ont pas besoin d'être réécrits.

### Script de mise à jour (`update.sh`)

La logique de mise à jour (pull git + rechargement de config) reste identique. Seuls les chemins cibles changent pour pointer vers `$VIDE_HOME` au lieu de `~/.config/nvim`.

### Japonette TUI

Le plugin Japonette (intégration 42 Intra API) est indépendant de Tmux. Il s'intègre dans Neovim directement et ne nécessite aucune modification pour fonctionner dans Vide.

### Dashboard Neovim

Le dashboard de bienvenue est réutilisé et enrichi pour le Mode IDE. La touche `u` pour mettre à jour est conservée. Le branding Nmux42 est remplacé par Vide.

```
Avant :  _   _                            _  _    ____
         | \ | | _ __ ___   _   _ __  __  | || |  |___ \
         ...

Après :  ██╗   ██╗██╗██████╗ ███████╗
         ██║   ██║██║██╔══██╗██╔════╝
         ...
```

### Logique 42 Network

Les trois adaptations spécifiques à l'environnement 42 sont précieuses et directement portées :

- **Sudo-free** : installation via `~/.local/bin`, Homebrew sans root
- **SSL fix** : `strict-ssl false` pour le proxy réseau 42
- **Node management** : upgrade automatique via `nvm` si la version système est trop ancienne

Ces logiques restent dans le script d'installation, conditionnées par une détection automatique de l'environnement 42.

---

## 🔄 Adapté

Ces éléments doivent être réécrits ou restructurés pour s'intégrer dans la nouvelle architecture.

### Script d'installation (`setup.sh`)

**Ce qui change :**

| Avant (Nmux42) | Après (Vide) |
|---------------|-------------------|
| Installe dans `~/.config/nvim` | Installe dans `~/.config/vide/` via `$NVIM_APPNAME` |
| Configure Tmux | Configure WezTerm |
| Modifie `.zshrc` directement | Crée un wrapper de lancement `vide` isolé |
| Pas de détection de config existante | Vérifie et préserve les dotfiles existants |

**Ce qui est conservé :**
- Détection OS (Arch / macOS / Linux générique)
- Logique d'installation sudo-free
- Gestion automatique du PATH
- Installation de JetBrainsMono Nerd Font
- Installation des LSP et compilateurs
- Routine de nettoyage des caches

**Nouvelle dépendance à installer :**
- WezTerm
- Yazi + `ya` CLI
- Rust (requis par Yazi)

```bash
# Nouveau flux d'installation simplifié
curl -fsSL https://vide.sh/install | sh
# ou
git clone https://github.com/Rouboufy/vide && cd vide && bash setup.sh
```

### Config Neovim (`nvim/`)

La base de plugins est conservée mais réorganisée. Les plugins liés à Tmux sont supprimés, de nouveaux plugins d'intégration WezTerm/Yazi sont ajoutés.

| Plugin | Statut | Raison |
|--------|--------|--------|
| Neo-tree | ❌ Retiré en Mode Zen | Remplacé par Yazi |
| Neo-tree | ⚠️ Fallback SSH | Conservé pour les sessions distantes |
| Telescope / Snacks.picker | ✅ Conservé | Fuzzy finder principal en Mode Zen |
| Lualine | ✅ Conservé | Adapté pour les deux modes |
| Harpoon | ✅ Conservé | Navigation rapide entre fichiers |
| LazyGit | ✅ Conservé | Intégration Git inchangée |
| Gitsigns | ✅ Conservé | Inchangé |
| LSP / Mason | ✅ Conservé | Inchangé |
| Japonette | ✅ Conservé | Inchangé |
| vim-tmux-navigator | ❌ Supprimé | Remplacé par la navigation WezTerm native |
| *nouveau* yazi.nvim | ➕ Ajouté | Bridge Neovim ↔ Yazi |
| *nouveau* barbecue.nvim | ➕ Ajouté | Breadcrumbs en Mode IDE |

### Sync de thème (`tmux-theme.sh`)

Le sync automatique de thème entre Neovim et Tmux était une feature phare de Nmux42. Elle est portée vers WezTerm.

**Avant :** `tmux-theme.sh` lit le thème actif Neovim et génère une config Tmux correspondante.

**Après :** Un hook Neovim écrit le thème actif dans un fichier d'état, WezTerm le lit via son API Lua et adapte ses couleurs (tabbar, bordures de panes, fond de terminal) en temps réel.

```lua
-- Hook Neovim : écrit le thème actif
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    local theme = vim.g.colors_name
    local f = io.open(os.getenv("HOME") .. "/.local/share/vide/theme.state", "w")
    if f then f:write(theme) f:close() end
  end
})
```

```lua
-- WezTerm : lit le thème et adapte les couleurs
wezterm.on("update-status", function(window, pane)
  local f = io.open(os.getenv("HOME") .. "/.local/share/vide/theme.state", "r")
  if f then
    local theme = f:read("*l")
    f:close()
    -- Appliquer la palette correspondante
  end
end)
```

### Keybindings

**Navigation entre panes :**

| Avant (Nmux42 + Tmux) | Après (Vide + WezTerm) |
|----------------------|----------------------------|
| `Alt + h/j/k/l` | `Alt + h/j/k/l` *(conservé)* |
| `Ctrl + a` prefix Tmux | Supprimé |
| vim-tmux-navigator | Navigation WezTerm native |

La navigation `Alt+h/j/k/l` est volontairement conservée à l'identique — les utilisateurs de Nmux42 ne perdent pas leur mémoire musculaire.

**Leader Space :**

| Raccourci | Avant | Après |
|-----------|-------|-------|
| `<leader>e` | Toggle Neo-tree | Toggle Yazi (Mode IDE) |
| `<leader>th` | Sélecteur de thème + sync Tmux | Sélecteur de thème + sync WezTerm |
| `<leader>ft` | Terminal flottant | Terminal flottant WezTerm |
| `<leader>gg` | LazyGit | LazyGit *(inchangé)* |
| *nouveau* `Space m t` | — | Toggle Mode IDE ↔ Mode Zen |
| *nouveau* `Space ?` | — | Tutoriel interactif |

---

## ❌ Abandonné

### Tmux (`tmux.conf` + `tmux-theme.sh`)

Tmux est remplacé par WezTerm dans son intégralité. WezTerm gère nativement la gestion des fenêtres, des splits, des onglets et du rendu GPU — sans la couche d'abstraction supplémentaire que représente Tmux.

**Pourquoi ce choix est définitif :**
- WezTerm = Tmux + émulateur de terminal + rendu GPU en un seul outil configuré en Lua
- La synchronisation de thème devient triviale sans pont inter-processus Tmux
- L'illusion d'application native (no-border) est impossible avec Tmux

> ⚠️ **Note pour les utilisateurs Nmux42 :** Tmux reste totalement fonctionnel en dehors de Vide. La migration ne supprime pas Tmux du système, elle ne l'utilise simplement plus.

---

## 🔁 Stratégie de Cohabitation

Nmux42 et Vide peuvent coexister sur la même machine sans conflit grâce à l'isolation des configs.

```
~/.config/
├── nvim/          ← Config Nmux42 (intacte)
├── tmux/          ← Config Nmux42 (intacte)
└── vide/
    ├── nvim/      ← Config Vide (isolée via $NVIM_APPNAME)
    └── wezterm/   ← Config WezTerm (isolée via $XDG_CONFIG_HOME)
```

**Lancer Nmux42 :** `nvim` dans n'importe quel terminal
**Lancer Vide :** `vide` (le wrapper de lancement dédié)

---

## 📋 Checklist de Migration

### Phase 1 — Préparation
- [ ] Fork du repo Nmux42 vers le nouveau repo Vide
- [ ] Renommer les références `Nmux42` → `Vide` dans tous les fichiers
- [ ] Créer la structure de dossiers isolée `~/.config/vide/`

### Phase 2 — Port des éléments stables
- [ ] Porter `update.sh` avec les nouveaux chemins
- [ ] Porter la config Neovim de base (sans les plugins Tmux)
- [ ] Vérifier que Japonette fonctionne dans le nouvel environnement
- [ ] Porter la logique 42 Network dans le nouveau `setup.sh`

### Phase 3 — Nouveaux composants
- [ ] Écrire la config WezTerm de base (no-border, tabs, splits)
- [ ] Intégrer Yazi dans un split WezTerm
- [ ] Implémenter l'IPC Yazi ↔ Neovim
- [ ] Porter le sync de thème vers WezTerm

### Phase 4 — Toggle de mode
- [ ] Implémenter `Space m t`
- [ ] Valider la persistance d'état entre sessions
- [ ] Tester le toggle sur macOS, Linux, WSL

### Phase 5 — Packaging final
- [ ] Écrire le nouveau `setup.sh` complet
- [ ] Écrire le `uninstall.sh` pour Vide
- [ ] Tester l'installation depuis zéro sur un environnement vierge
- [ ] Tester la cohabitation Nmux42 + Vide sur la même machine

---

## 🧪 Plan de Tests de Non-Régression

Avant chaque release, vérifier que les fonctionnalités clés de Nmux42 sont équivalentes ou améliorées dans Vide :

| Feature Nmux42 | Équivalent Vide | Validé |
|---------------|---------------------|--------|
| Installation one-command | `curl \| sh` ou `bash setup.sh` | ⬜ |
| Sudo-free sur 42 cluster | Conservé dans `setup.sh` | ⬜ |
| Navigation `Alt+h/j/k/l` | WezTerm natif | ⬜ |
| Sync thème Neovim ↔ shell | Neovim ↔ WezTerm | ⬜ |
| Sélecteur de thème `Space th` | Conservé + sync WezTerm | ⬜ |
| LazyGit `Space gg` | Inchangé | ⬜ |
| Japonette `Space Ja` | Inchangé | ⬜ |
| Update depuis le dashboard | Conservé | ⬜ |
| Uninstall propre | Nouveau `uninstall.sh` | ⬜ |

---

*Document vivant — mis à jour à chaque étape de la migration.*
