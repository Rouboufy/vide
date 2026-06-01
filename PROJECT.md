#  Vide — Project Specification

> Ce document résume la vision, l'architecture technique et les choix d'implémentation de Vide.
> Stack : Zig + Neovim embarqué. Zéro dépendance externe à l'exécution.

---

##  Vision du Projet

La plupart des IDE modernes font un choix : soit ils sont accessibles, soit ils sont puissants. VS Code a choisi l'accessibilité. Neovim a choisi la puissance. **Vide refuse de choisir.**

L'objectif est de construire un environnement de développement qui s'adresse à tout le monde — du débutant complet au développeur confirmé — sans jamais faire de compromis sur les performances, la légèreté ou la philosophie Unix.

### Comment ?

En proposant **deux faces d'une même application** :

**La face visible (Mode IDE)** ressemble à n'importe quel IDE moderne. Arbre de fichiers à gauche, onglets en haut, diagnostics d'erreurs en bas, tout est cliquable à la souris. Un utilisateur habitué à VS Code s'y retrouve immédiatement.

**La face cachée (Mode Zen)** est accessible en un raccourci. L'interface disparaît, le terminal reprend le contrôle total. C'est l'environnement des power users, des sessions SSH, des sysadmins — vitesse maximale, zéro distraction.

> Le Mode IDE est la porte d'entrée. Le Mode Zen est la récompense.

---

## 🏗️ Architecture Technique

Vide est une **application Zig unique** qui embarque Neovim comme moteur d'édition via son protocole natif `--embed`. Aucun outil tiers n'est requis à l'exécution hormis Neovim lui-même.

```
┌─────────────────────────────────────────────────────────┐
│                    VIDE (binaire Zig)                   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │                  TUI RENDERER                   │    │
│  │     Raw VT sequences · Mouse · Keyboard         │    │
│  └──────────────────────┬──────────────────────────┘    │
│                         │                               │
│  ┌──────────┬───────────┼──────────────┬────────────┐   │
│  │ ACTIVITY │   FILE    │    EDITOR    │   STATUS   │   │
│  │   BAR    │   TREE    │    PANEL     │    BAR     │   │
│  │  (Zig)   │  (Zig)    │  (Neovim     │   (Zig)    │   │
│  │          │           │  viewport)   │            │   │
│  └──────────┴───────────┴──────┬───────┴────────────┘   │
│                                │                        │
│  ┌─────────────────────────────▼──────────────────┐     │
│  │              NEOVIM RPC LAYER (Zig)            │     │
│  │        msgpack-rpc · nvim --embed              │     │
│  └────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
               Neovim subprocess
               (LSP · Treesitter · Plugins)
```

### Le Stack

**Vide (Zig)** — L'application principale. Gère le rendu TUI, les inputs, le layout, les widgets, et la communication avec Neovim via msgpack-rpc.

**Neovim** — Le moteur d'édition. Lancé en mode `--embed`, il n'a pas d'interface propre. Vide est son seul frontend. LSP, Treesitter, plugins Lua — tout est conservé.

**C'est tout.**

---

##  Les Deux Modes de l'Interface

### 1. Mode IDE *(par défaut)*

```
┌────┬──────────────┬───────────────────────────────┐
│    │  EXPLORER    │                               │
│ A  │              │         NEOVIM                │
│ C  │  ∨ src       │                               │
│ T  │    main.zig  │                               │
│ B  │    build.zig │                               │
│ A  │              │                               │
│ R  │              ├───────────────────────────────┤
│    │              │ PANEL (diagnostics / terminal)│
├────┴──────────────┴───────────────────────────────┤
│              STATUS BAR                           │
└───────────────────────────────────────────────────┘
```

- Activity Bar cliquable à gauche
- File tree natif Zig (lecture directe `std.fs`)
- Viewport Neovim avec tab bar
- Status bar style VS Code (`#007ACC`)
- Tout accessible à la souris

### 2. Mode Zen

```
┌───────────────────────────────────────────────────┐
│                                                   │
│                    NEOVIM                         │
│               (plein écran)                       │
│                                                   │
└───────────────────────────────────────────────────┘
```

- Activity bar masquée
- File tree masqué
- Neovim occupe 100% de l'espace
- Fuzzy finder pour naviguer (`Space ff`)

Toggle : `Space m t`

---

##  Stack Technique Détaillé

| Composant | Technologie | Pourquoi |
|-----------|-------------|----------|
| Langage | Zig | Contrôle total, binaire unique, interop C excellent |
| Rendu TUI | VT/ANSI sequences (Zig pur) | Zéro dépendance C, ~300 lignes, contrôle total |
| Éditeur | Neovim `--embed` | LSP, Treesitter, plugins — réinventer la roue serait absurde |
| Protocole | msgpack-rpc (Zig pur) | Implémentation légère ~500 lignes |
| File tree | `std.fs` Zig | Natif, rapide, pas de processus externe |
| Git status | `git status --porcelain` parsé | Simple, fiable |
| Config | TOML parsé en Zig | Format universel, lisible |

---

##  Mécaniques Clés

### Rendu Double Buffer
Vide maintient deux buffers de cellules (actuel + précédent). Au flush, seules les cellules modifiées sont envoyées au terminal — zéro scintillement, performance maximale.

### Neovim UI Protocol
Via `nvim_ui_attach` avec `ext_linegrid`, Neovim envoie son contenu sous forme de grille RGB. Vide reçoit ces events `redraw` et les applique dans son renderer, dans la zone dédiée au viewport éditeur.

### File Tree Natif
Le file tree lit `std.fs` directement. Pas de processus externe, pas d'IPC. Les nœuds sont expandables/collapsables en mémoire. Le git status est rafraîchi en arrière-plan via `std.process.exec`.

### Layout Engine
Le layout est calculé à partir des dimensions du terminal (`TIOCGWINSZ`). Chaque widget reçoit un `Rect` et dessine dedans. Un resize terminal recalcule tout instantanément.

---

##  Distribution

```bash
curl -fsSL https://vide.sh/install | sh
```

- Binaire unique (~2-5 MB)
- Compatible macOS, Linux, WSL
- Pas de sudo requis
- N'écrase jamais les configs Neovim existantes (`$NVIM_APPNAME=vide`)
- Fonctionne nativement en SSH (TUI pur)

---

##  Roadmap

```
Phase 1 — TUI de base
  ├── Raw mode terminal
  ├── Renderer double buffer
  └── Input clavier + souris

Phase 2 — Neovim RPC
  ├── msgpack encode/decode
  ├── nvim --embed + ui_attach
  └── Afficher Neovim dans le renderer ← milestone critique

Phase 3 — Widgets
  ├── Layout engine
  ├── Activity bar
  ├── File tree
  ├── Tab bar
  ├── Status bar
  └── Terminal panel

Phase 4 — Intégration
  ├── Clic file tree → ouvre dans Neovim
  ├── Toggle IDE ↔ Zen
  ├── Gestion des paramètres (Persistent settings)
  └── Resize adaptatif

Phase 5 — Distribution
  ├── Build multi-OS
  ├── Script d'installation
  └── Config Neovim isolée
```

---

## ⚖️ Licence

**MIT** — Adoption libre, contributions bienvenues.

---

*Document vivant — référence principale du projet Vide.*
