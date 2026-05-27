# 🎨 Design Specification — Vide *(or Rift)*

> Référence visuelle officielle pour le Mode IDE.
> Cible : reproduire l'apparence de VSCodium / VS Code au point qu'un utilisateur habituel ne voit pas la différence au premier coup d'œil.
> Source : screenshot VSCodium (Dark Modern theme) — `screenshot-2026-05-27_16-35-57.png`

---

## 🎯 Objectif

L'utilisateur qui ouvre Vide pour la première fois doit avoir l'impression d'ouvrir un éditeur moderne standard. Aucun élément ne doit trahir le stack terminal sous-jacent en Mode IDE.

---

## 🖼️ Layout Global

```
┌──────────────────────────────────────────────────────────────────┐
│                        TITLE BAR (WezTerm)                       │  22px
├────┬─────────────────────────────────────────────────────────────┤
│    │                    TAB BAR (WezTerm)                        │  35px
│    ├──────────────────────────────────────────────────────────── ┤
│ A  │                                                             │
│ C  │                                                             │
│ T  │                 EDITOR AREA (Neovim)                        │  flex
│ I  │                                                             │
│ V  │                                                             │
│ I  ├──────────────────────────────────────────────────────────── ┤
│ T  │                  PANEL AREA (Neovim)                        │  180px (toggle)
│ Y  ├──────────────────────────────────────────────────────────── ┤
│    │                 STATUS BAR (lualine)                        │  22px
├────┴─────────────────────────────────────────────────────────────┤
     ▲
     └── ACTIVITY BAR (40px) + FILE EXPLORER / YAZI (220px)
```

---

## 🎨 Palette de Couleurs

> Reproduire exactement la palette Dark Modern de VS Code.

### Couleurs principales

| Token | Hex | Utilisation |
|-------|-----|-------------|
| `bg.editor` | `#1E1E1E` | Fond de l'éditeur Neovim |
| `bg.sidebar` | `#252526` | Fond Yazi + Activity Bar |
| `bg.tab.inactive` | `#2D2D2D` | Onglets WezTerm inactifs |
| `bg.tab.active` | `#1E1E1E` | Onglet WezTerm actif |
| `bg.statusbar` | `#007ACC` | Statusline lualine (bleu VS Code) |
| `bg.panel` | `#1E1E1E` | Panneau bas (outline, terminal) |
| `border` | `#3C3C3C` | Séparations entre panes |
| `fg.primary` | `#D4D4D4` | Texte principal |
| `fg.secondary` | `#858585` | Texte désactivé, commentaires |
| `fg.accent` | `#CCCCCC` | Titres de section (EXPLORER) |
| `fg.statusbar` | `#FFFFFF` | Texte statusline |
| `cursor` | `#AEAFAD` | Curseur éditeur |
| `selection` | `#264F78` | Sélection de texte |
| `indent.guide` | `#404040` | Guides d'indentation |

### Couleurs syntaxiques (Neovim Treesitter)

| Token | Hex | Exemple |
|-------|-----|---------|
| Keywords | `#569CD6` | `if`, `for`, `return` |
| Strings | `#CE9178` | `"hello world"` |
| Numbers | `#B5CEA8` | `42`, `3.14` |
| Functions | `#DCDCAA` | `myFunction()` |
| Types | `#4EC9B0` | `int`, `string`, `bool` |
| Variables | `#9CDCFE` | `myVar` |
| Comments | `#6A9955` | `// comment` |
| Operators | `#D4D4D4` | `+`, `=`, `=>` |

> 💡 Ces couleurs correspondent au thème `vscode-dark` disponible dans plusieurs distributions Neovim. Plugin recommandé : [`Mofiqul/vscode.nvim`](https://github.com/Mofiqul/vscode.nvim)

---

## 🏗️ Composants — Spécification Détaillée

### 1. Activity Bar *(barre verticale, côté gauche)*

**Dimensions :** 40px de large, hauteur totale de l'écran
**Fond :** `#252526`
**Séparation droite :** bordure `1px solid #3C3C3C`

**Icônes (de haut en bas) :**

| Position | Icône | Action |
|----------|-------|--------|
| 1 | `󰙅` Files | Toggle Yazi |
| 2 | `` Search | Telescope live grep |
| 3 | `󰊢` Source Control | LazyGit |
| 4 | `` Debug | DAP |
| 5 | `` Extensions | Mason |
| bas | `` Profile | — |

**État actif :** icône couleur `#CCCCCC`, bordure gauche `2px solid #CCCCCC`
**État inactif :** icône couleur `#858585`

> ⚙️ **Implémentation :** L'Activity Bar est un split WezTerm ultra-étroit (40px) OU une colonne Neovim décorative. Option la plus propre : intégrée dans le layout Neovim via un plugin comme `bufferline.nvim` avec icônes latérales.

---

### 2. File Explorer / Yazi *(panel gauche)*

**Dimensions :** 220px de large (≈ 27 colonnes de terminal)
**Fond :** `#252526`
**Séparation droite :** `1px solid #3C3C3C`

**Header :**
```
  EXPLORER                    ...
  ∨ PROJECT_NAME
```
- Texte `EXPLORER` en majuscules, taille 11px, `#BBBBBB`, letterspacing élargi
- Icône `...` (options) à droite, visible au hover

**Arborescence :**
- Icônes de fichiers via Nerd Fonts (`󰌆` `.lua`, `` `.js`, `` `.py`…)
- Indentation : 16px par niveau
- Item actif : fond `#37373D`, texte `#FFFFFF`
- Item hover : fond `#2A2D2E`
- Couleur dossier : `#C5C5C5`
- Couleur fichier modifié (Git) : `#E2C08D`
- Couleur fichier nouveau (Git) : `#73C991`

> ⚙️ **Implémentation :** Yazi dans un split WezTerm. Config `~/.config/vide/yazi/theme.toml` avec les couleurs ci-dessus.

---

### 3. Tab Bar *(WezTerm)*

**Hauteur :** 35px
**Fond général :** `#252526`

**Onglet actif :**
- Fond : `#1E1E1E`
- Texte : `#FFFFFF`
- Bordure top : `1px solid #007ACC` ← détail signature VS Code
- Icône de fichier à gauche
- `×` de fermeture à droite (visible au hover)

**Onglet inactif :**
- Fond : `#2D2D2D`
- Texte : `#969696`
- Pas de bordure top

**Boutons de navigation (←→) :**
- Fond : `#252526`
- Positionnés à gauche de la barre d'onglets

```lua
-- wezterm.lua
config.tab_bar_at_bottom = false
config.use_fancy_tab_bar = false
config.tab_max_width = 32
config.colors = {
  tab_bar = {
    background = "#252526",
    active_tab = {
      bg_color = "#1E1E1E",
      fg_color = "#FFFFFF",
    },
    inactive_tab = {
      bg_color = "#2D2D2D",
      fg_color = "#969696",
    },
    inactive_tab_hover = {
      bg_color = "#2A2D2E",
      fg_color = "#CCCCCC",
    },
  },
}
```

---

### 4. Editor Area *(Neovim)*

**Fond :** `#1E1E1E`
**Police :** JetBrainsMono Nerd Font, taille 13px, ligatures activées
**Hauteur de ligne :** 1.5
**Numéros de ligne :** relatifs, couleur `#858585`, actif `#C6C6C6`
**Curseur :** bloc en mode Normal, ligne en mode Insert
**Guides d'indentation :** `#404040` (plugin `indent-blankline.nvim`)
**Ruler (colonne 80/120) :** `#3C3C3C`

**Winbar (breadcrumbs) :**
```
 src  >  components  >  Button.tsx  >  export function Button
```
- Fond : `#252526`
- Texte : `#858585`, élément actif `#CCCCCC`
- Plugin : `barbecue.nvim`

**Buffer vide / Dashboard :**
```
                    ██╗   ██╗██╗██████╗ ███████╗
                    ██║   ██║██║██╔══██╗██╔════╝
                    ██║   ██║██║██║  ██║█████╗
                    ╚██╗ ██╔╝██║██║  ██║██╔══╝
                     ╚████╔╝ ██║██████╔╝███████╗
                      ╚═══╝  ╚═╝╚═════╝ ╚══════╝

              Show All Commands          Space Space
              Find Files                 Space f f
              Open Recent                Space f r
              Open Settings              Space ,
              New File                   Ctrl + N
```
- Centré verticalement et horizontalement
- Logo couleur `#3C3C3C` (subtil, comme le watermark VSCodium)
- Raccourcis : label `#858585`, key badge fond `#3C3C3C` texte `#CCCCCC`

---

### 5. Panel Area *(bas de l'éditeur, Neovim)*

**Hauteur par défaut :** 180px (toggle avec `Space j`)
**Fond :** `#1E1E1E`
**Bordure top :** `1px solid #3C3C3C`

**Onglets du panel :**
```
  OUTLINE    TIMELINE    TERMINAL    PROBLEMS
```
- Onglet actif : texte `#CCCCCC`, bordure bottom `2px solid #007ACC`
- Onglet inactif : texte `#858585`

**Plugins associés :**
- `OUTLINE` → `aerial.nvim` ou `symbols-outline.nvim`
- `PROBLEMS` → `trouble.nvim`
- `TERMINAL` → terminal intégré WezTerm split horizontal

---

### 6. Status Bar *(lualine)*

**Hauteur :** 22px
**Fond gauche :** `#007ACC` ← **le bleu signature VS Code, incontournable**
**Fond droite :** `#252526`

**Contenu gauche → droite :**
```
  main   src/components/Button.tsx    Ln 42, Col 8    Spaces: 2    UTF-8    TypeScript
```

**Contenu droit → gauche :**
```
⊗ 0   ⚠ 2   Prettier   Git: main ↑1
```

```lua
-- lualine config cible
sections = {
  lualine_a = { { "mode", color = { bg = "#007ACC", fg = "#FFFFFF" } } },
  lualine_b = { "branch", "diff" },
  lualine_c = { { "filename", path = 1 } },
  lualine_x = { "diagnostics", "encoding", "fileformat", "filetype" },
  lualine_y = { "progress" },
  lualine_z = { "location" },
}
```

---

### 7. Window Chrome *(WezTerm)*

**Bordures de fenêtre :** aucune (`window_decorations = "NONE"`)
**Padding interne :** 0px sur tous les côtés
**Ombre portée :** gérée par le compositeur OS (macOS/GNOME)
**Coins :** arrondis si supporté par le WM

```lua
-- wezterm.lua
config.window_decorations = "NONE"
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
config.initial_cols = 220
config.initial_rows = 50
```

---

## 🔤 Typographie

| Usage | Police | Taille | Style |
|-------|--------|--------|-------|
| Code | JetBrainsMono Nerd Font | 13px | Regular + ligatures |
| UI (tabs, sidebar) | JetBrainsMono Nerd Font | 11px | Regular |
| Statusline | JetBrainsMono Nerd Font | 11px | Regular |

```lua
-- wezterm.lua
config.font = wezterm.font("JetBrainsMono Nerd Font", { weight = "Regular" })
config.font_size = 13.0
config.harfbuzz_features = { "calt=1", "clig=1", "liga=1" } -- ligatures
```

---

## 📐 Dimensions de Référence (fenêtre 1440px)

| Zone | Largeur | Hauteur |
|------|---------|---------|
| Activity Bar | 40px | 100% |
| File Explorer (Yazi) | 220px | 100% |
| Editor Area | ~1180px | ~100% |
| Title Bar | 100% | 22px |
| Tab Bar | 100% | 35px |
| Status Bar | 100% | 22px |
| Panel (ouvert) | 100% | 180px |

---

## ✅ Checklist d'Implémentation Visuelle

### WezTerm
- [ ] Palette de couleurs tab bar (actif / inactif / hover)
- [ ] Bordure top bleue `#007ACC` sur l'onglet actif
- [ ] `window_decorations = "NONE"`
- [ ] `window_padding` à 0 partout
- [ ] Police JetBrainsMono + ligatures
- [ ] Split Yazi à 220px fixe côté gauche

### Neovim
- [ ] Thème `vscode.nvim` (Mofiqul) configuré
- [ ] `lualine.nvim` avec statusline bleue
- [ ] `barbecue.nvim` pour les breadcrumbs
- [ ] `indent-blankline.nvim` avec guides `#404040`
- [ ] `trouble.nvim` pour le panel PROBLEMS
- [ ] `aerial.nvim` pour le panel OUTLINE
- [ ] Dashboard centré avec logo watermark

### Yazi
- [ ] `theme.toml` avec la palette VS Code Dark
- [ ] Icônes Nerd Fonts activées
- [ ] Header `EXPLORER` en majuscules
- [ ] Couleurs Git (modifié / nouveau)

---

*Ce fichier est la référence absolue pour toute décision visuelle en Mode IDE. En cas de doute : coller au plus près du screenshot VSCodium cible.*
