# ⚙️ Vide — Technical Challenges

> Ce document recense les défis techniques identifiés, leur niveau de complexité, les approches envisagées et les risques associés. Il sert de feuille de route pour les décisions d'implémentation critiques.

---

## 🗺️ Vue d'ensemble

| # | Défi | Complexité | Priorité |
|---|------|-----------|----------|
| 1 | Interception du Leader unifié (Space) | 🔴 Haute | P0 |
| 2 | Communication IPC Yazi ↔ Neovim | 🔴 Haute | P0 |
| 3 | Toggle de mode sans perte d'état | 🟠 Moyenne | P1 |
| 4 | Isolation du packaging multi-OS | 🟠 Moyenne | P1 |
| 5 | Illusion d'application native (no-border) | 🟡 Faible | P2 |
| 6 | Synchronisation de l'arbre de fichiers | 🟠 Moyenne | P1 |
| 7 | Expérience premier lancement (onboarding) | 🟡 Faible | P2 |
| 8 | Support SSH en mode Zen | 🔴 Haute | P2 |

---

## 1. 🎹 Interception du Leader Unifié (Space)

### Le problème

La touche `Space` est le leader de Neovim. Elle est aussi censée déclencher des actions WezTerm (navigation entre panes, toggle de mode, gestion des onglets). Ces deux couches d'interception se marchent dessus.

WezTerm capture les inputs **avant** qu'ils atteignent Neovim. Il faut donc lui apprendre à ne **pas** capturer `Space` quand Neovim a le focus — sauf pour les combinaisons globales définies.

### Approches envisagées

**Option A — Liste blanche WezTerm**
Définir explicitement dans la config WezTerm la liste exhaustive des combinaisons `Space + X` qui lui appartiennent. Tout le reste est passé à Neovim.
- ✅ Simple à comprendre
- ❌ Fragile : chaque nouveau raccourci Neovim doit être vérifié contre cette liste

**Option B — Tracking d'état via le titre du pane** *(recommandée)*
Neovim met à jour le titre du pane WezTerm en temps réel pour indiquer son mode courant (Normal, Insert, Visual…). WezTerm lit ce titre pour décider d'intercepter ou non.
- ✅ Découplage propre, pas de liste à maintenir
- ❌ Légère latence de synchronisation du titre possible

**Option C — Deux leaders distincts**
`Space` pour Neovim, `Ctrl+Space` pour WezTerm. Abandon du leader unifié.
- ✅ Zéro conflit
- ❌ Casse la philosophie du projet

### Décision recommandée

Option B avec un fallback sur Option A pour les cas limites. La variable de titre pane est déjà supportée nativement par WezTerm via `wezterm.mux.get_active_pane():get_title()`.

### Risques

- Latence du titre pane en cas de charge CPU élevée
- Comportement non défini si Neovim plante sans remettre le titre à l'état initial

---

## 2. 🔌 Communication IPC Yazi ↔ Neovim

### Le problème

Yazi et Neovim sont deux processus indépendants. Pour donner l'illusion d'un IDE unifié, ils doivent se parler en temps réel dans les deux sens — et ce de manière fiable, même dans des conditions dégradées.

### Canal Yazi → Neovim

**Objectif :** Quand l'utilisateur ouvre un fichier dans Yazi, Neovim l'ouvre dans son panneau principal.

**Implémentation :**
```bash
# Yazi exécute cette commande à l'ouverture d'un fichier
nvim --server /tmp/vide_nvim.pipe --remote "$FILE_PATH"
```

**Cas d'erreur à gérer :**
- Le socket n'existe pas encore (Neovim pas encore démarré) → retry avec backoff exponentiel
- Plusieurs sockets actifs (plusieurs instances Neovim) → détection de l'instance active via le PID du pane WezTerm parent
- Chemin de fichier avec espaces ou caractères spéciaux → échappement systématique

### Canal Neovim → Yazi

**Objectif :** Quand Neovim change de buffer, Yazi synchronise son arborescence sur le dossier du fichier actif.

**Implémentation :**
```lua
-- Dans init.lua Neovim
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function()
    local dir = vim.fn.expand("%:p:h")
    vim.fn.jobstart({ "ya", "emit", "cd", dir })
  end
})
```

**Cas d'erreur à gérer :**
- Buffer sans fichier associé (terminal intégré, buffer scratch) → ignorer les paths vides ou `[No Name]`
- `ya` non disponible dans le PATH → vérification au démarrage avec message d'erreur lisible
- Boucle infinie si Yazi déclenche un BufEnter en retour → flag de guard

### Risques globaux

- Désynchronisation silencieuse si un processus crashe
- Comportement imprévisible en cas de rename/move de fichier en cours d'édition

---

## 3. 🔄 Toggle de Mode Sans Perte d'État

### Le problème

Basculer entre Mode IDE et Mode Zen doit être **instantané et réversible**. L'utilisateur ne doit perdre ni ses buffers ouverts, ni sa position dans Yazi, ni son historique de navigation.

### Ce qui doit être préservé

| Élément | Mode IDE → Zen | Mode Zen → IDE |
|---------|---------------|----------------|
| Buffers Neovim ouverts | ✅ Intacts | ✅ Intacts |
| Position curseur | ✅ Intacte | ✅ Intacte |
| Répertoire courant Yazi | 💾 Sauvegardé | 🔄 Restauré |
| Onglets WezTerm | 👁️ Masqués | 👁️ Réaffichés |
| Split Yazi | ❌ Fermé | 🔄 Réouvert |

### Approche recommandée

Stocker l'état du mode dans une variable WezTerm persistante et dans un fichier d'état léger :

```lua
-- wezterm.lua
local mode = wezterm.GLOBAL.current_mode or "ide"

wezterm.on("toggle-mode", function(window, pane)
  if mode == "ide" then
    -- Fermer le split Yazi, masquer les tabs
    mode = "zen"
  else
    -- Rouvrir le split Yazi, afficher les tabs
    mode = "ide"
  end
  wezterm.GLOBAL.current_mode = mode
end)
```

### Risques

- Réouverture du split Yazi trop lente si le dossier précédent contenait beaucoup de fichiers
- Désynchronisation possible si le toggle est déclenché pendant une opération I/O Yazi

---

## 4. 📦 Isolation du Packaging Multi-OS

### Le problème

WezTerm, Neovim et Yazi ont chacun leurs propres chemins de configuration. L'installation ne doit **jamais** écraser les dotfiles existants de l'utilisateur.

### Chemins problématiques par OS

| Composant | Linux | macOS | WSL |
|-----------|-------|-------|-----|
| Neovim | `~/.config/nvim` | `~/.config/nvim` | `~/.config/nvim` |
| WezTerm | `~/.config/wezterm` | `~/.config/wezterm` | `~/.config/wezterm` |
| Yazi | `~/.config/yazi` | `~/.config/yazi` | `~/.config/yazi` |

### Solution

**Neovim** → `$NVIM_APPNAME=vide` redirige vers `~/.config/vide/nvim`

**WezTerm** → Script wrapper de lancement qui surcharge `XDG_CONFIG_HOME` :
```bash
#!/bin/bash
# /usr/local/bin/vide
export XDG_CONFIG_HOME="$HOME/.config/vide"
export NVIM_APPNAME="vide-nvim"
exec wezterm start -- nvim "$@"
```

**Yazi** → Variable `YAZI_CONFIG_HOME` (supportée nativement depuis Yazi 0.3+)

### Risques

- `XDG_CONFIG_HOME` surchargée peut affecter d'autres applications lancées depuis WezTerm
- Sur macOS, WezTerm peut aussi lire depuis `~/Library/Application Support/` → vérification nécessaire

---

## 5. 🖼️ Illusion d'Application Native (No-Border)

### Le problème

Pour qu'un utilisateur non-technique ne réalise pas qu'il est dans un terminal, WezTerm doit ressembler à une application native : pas de barre de titre OS, pas de chrome visible, coins arrondis, ombre portée.

### Implémentation WezTerm

```lua
-- wezterm.lua
config.window_decorations = "NONE"
config.window_background_opacity = 1.0
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
```

### Problèmes connus par OS

| OS | Problème | Contournement |
|----|----------|---------------|
| macOS | Perte du drag de fenêtre sans barre de titre | `window_decorations = "RESIZE"` ou zone de drag custom |
| Linux (X11) | Dépend du window manager | Testé sur GNOME, KWin, i3 |
| Linux (Wayland) | Décoration gérée par le compositeur | `"NONE"` peut ne pas fonctionner partout |
| WSL | Rendu via Windows → artefacts possibles | Tests nécessaires sur Windows 11 |

### Risques

- Sur certains environnements Wayland, le mode sans bordure est ignoré
- La fenêtre sans barre de titre peut perturber les utilisateurs qui tentent de la déplacer

---

## 6. 🌳 Synchronisation de l'Arbre de Fichiers

### Le problème

Yazi doit toujours refléter le contexte actuel de Neovim. Certains événements peuvent désynchroniser les deux : renommage de fichier, déplacement, création depuis le terminal intégré, ou changement de projet via un session manager.

### Événements à intercepter

| Événement Neovim | Action Yazi requise |
|-----------------|---------------------|
| `BufEnter` | `ya emit cd <dir>` |
| `:cd` / `:lcd` | `ya emit cd <new_dir>` |
| Renommage via LSP | Reload de l'arborescence |
| Session restore | `ya emit cd <project_root>` |

### Détection du project root

Utiliser les marqueurs standards dans cet ordre de priorité :
1. `.git`
2. `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`
3. Dossier courant de Neovim en fallback

---

## 7. 🚀 Expérience Premier Lancement (Onboarding)

### Le problème

Un utilisateur venant de VS Code ne sait pas ce qu'est un socket RPC, un leader key, ou un pane WezTerm. Il doit pouvoir utiliser l'application immédiatement, sans documentation préalable.

### Approche recommandée

**Étape 1 — Détection du premier lancement**
Vérifier l'absence du fichier `~/.local/share/vide/.initialized`.

**Étape 2 — Écran de bienvenue**
Un buffer Neovim spécial (non sauvegardable, non listable) s'ouvre avec :
- Un message de bienvenue court
- Les 5 raccourcis essentiels en mode IDE
- Un bouton `[Commencer →]` cliquable à la souris

**Étape 3 — Tutoriel optionnel**
Proposer un tutoriel interactif guidé (`Space ?`) accessible à tout moment, jamais imposé.

### Risques

- L'écran de bienvenue peut être perçu comme intrusif par les power users → le désactiver si `$VIDE_SKIP_INTRO=1`

---

## 8. 🌐 Support SSH en Mode Zen

### Le problème

En mode Zen, l'utilisateur doit pouvoir se connecter à un serveur distant et retrouver un environnement cohérent. Mais Yazi, WezTerm et le stack complet ne sont disponibles que localement.

### Ce qui fonctionne nativement en SSH

- Neovim seul → fonctionne parfaitement
- Configurations Neovim → transmissibles via `rsync` ou un script de bootstrap

### Ce qui ne fonctionne pas

- Yazi → non disponible côté serveur (à moins d'être installé)
- WezTerm splits → contrôle local uniquement
- IPC Yazi ↔ Neovim → impossible à distance sans tunnel

### Approche recommandée

En session SSH, basculer automatiquement en **mode Neovim pur** :
- Désactiver l'IPC
- Proposer `oil.nvim` ou `neo-tree` comme fallback de file explorer intégré à Neovim
- Documenter un script de bootstrap pour installer Neovim + config sur le serveur cible

### Risques

- L'expérience SSH est significativement dégradée par rapport au mode local
- Complexité de maintenance de deux code paths (local vs SSH)

---

## 📋 Plan d'Implémentation Recommandé

```
Phase 1 — Foundation (Mode IDE statique)
  ├── Config WezTerm no-border + tabs
  ├── Config Neovim de base (LSP, Treesitter, statusline)
  └── Yazi dans un split WezTerm fixe

Phase 2 — IPC de base
  ├── Yazi → Neovim (ouverture de fichier)
  └── Neovim → Yazi (sync BufEnter)

Phase 3 — Toggle de mode
  ├── Space m t fonctionnel
  └── Persistance de l'état entre sessions

Phase 4 — Packaging & Onboarding
  ├── Script d'installation isolé (vide)
  ├── Écran de bienvenue
  └── Tests multi-OS (macOS, Ubuntu, WSL)

Phase 5 — Polish & SSH
  ├── Leader unifié robuste
  ├── Gestion des edge cases IPC
  └── Mode SSH dégradé graceful
```

---

*Document vivant — mis à jour au fil des décisions d'implémentation et des découvertes terrain.*
