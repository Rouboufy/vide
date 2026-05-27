# 🛠️ Vide — Project Specification

> Ce document résume la vision, l'architecture technique et les choix d'implémentation pour la création d'un environnement de développement desktop léger, ultra-rapide et verticalement intégré, basé sur l'écosystème terminal moderne.

---

## 🎯 Vision du Projet

La plupart des IDE modernes font un choix : soit ils sont accessibles, soit ils sont puissants. VS Code a choisi l'accessibilité. Neovim a choisi la puissance. **Vide refuse de choisir.**

L'objectif est de construire un environnement de développement qui s'adresse à tout le monde — du débutant complet au développeur confirmé — sans jamais faire de compromis sur les performances, la légèreté ou la philosophie Unix.

### Comment ?

En proposant **deux faces d'une même application** :

**La face visible (Mode IDE)** ressemble à n'importe quel IDE moderne. Arbre de fichiers à gauche, onglets en haut, diagnostics d'erreurs en bas, tout est cliquable à la souris. Un utilisateur habitué à VS Code ou Cursor s'y retrouve immédiatement, sans jamais réaliser qu'il tourne sur un stack terminal.

**La face cachée (Mode Zen)** est accessible en un raccourci. L'interface disparaît, le terminal reprend le contrôle total. C'est l'environnement des power users, des sessions SSH, des sysadmins — vitesse maximale, zéro distraction, mémoire musculaire pure.

> Le Mode IDE est la porte d'entrée. Le Mode Zen est la récompense.

L'application est installable en une commande, isolée des dotfiles existants de l'utilisateur, et ne demande aucune connaissance préalable de Neovim ou du terminal pour être utilisée dès le premier lancement.

La progression est naturelle : un utilisateur commence en mode IDE, découvre la puissance sous-jacente à son rythme, et bascule vers le mode Zen quand il est prêt — ou jamais, et c'est très bien aussi.

---

## 🏗️ Architecture Technique — The Stack

Le projet repose sur la synergie de trois composants majeurs, tous configurables en **Lua**, garantissant une cohérence absolue du code et de la maintenance.

```
       +---------------------------------------------+
       |                  WEZTERM                    |
       |  (Fenêtre GUI, Rendu GPU, Gestion de l'UX)  |
       +---------------------------------------------+
                            |
             +--------------+--------------+
             |                             |
             v                             v
     +---------------+             +---------------+
     |     YAZI      |             |    NEOVIM     |
     | (File Tree /  |  <--RPC-->  | (Éditeur, LSP,|
     |  Pane Gauche) |             |  Treesitter)  |
     +---------------+             +---------------+
```

### 1. Rendu & Interface : WezTerm

- **Rôle :** Serveur graphique, émulateur de terminal principal et orchestrateur des fenêtres/splits.
- **Pourquoi ?** Rendu GPU ultra-fluide, support natif du protocole d'images, configuration en Lua, gestion fine des polices et des ligatures. Il sert de "wrapper" graphique (sans bordures de fenêtre) pour donner l'illusion d'une application native standard.

### 2. Éditeur de Code : Neovim

- **Rôle :** Cœur de l'édition, intégration des serveurs de langage (LSP), coloration syntaxique avancée (Treesitter), débogage et workflow de développement.
- **Pourquoi ?** Vitesse d'exécution imbattable, écosystème de plugins Lua mature, et extensibilité via sockets RPC.

### 3. Arbre de Fichiers : Yazi

- **Rôle :** Exploration des fichiers déportée dans un panneau latéral WezTerm natif (split gauche).
- **Pourquoi ?** Écrit en Rust avec des I/O asynchrones, Yazi garantit qu'aucun chargement de dossier lourd ne viendra jamais bloquer ou ralentir le thread principal de Neovim. Configurable en Lua, il s'intègre parfaitement à WezTerm pour le rendu d'icônes et d'images.

---

## 🔄 Les Deux Modes de l'Interface

L'application propose une transition instantanée entre deux agencements visuels via un raccourci global (`Space m t` — Mode Toggle), sans jamais dupliquer les raccourcis ou perdre la configuration de fond.

### 1. Le Mode IDE *(par défaut — Assisté et Visuel)*

**Mode d'entrée de l'application.** Pensé pour être immédiatement familier à tout développeur venant d'un IDE classique. Tout est accessible à la souris, aucune connaissance du terminal n'est requise.

**Composants activés :**
- **WezTerm :** Barre d'onglets moderne en haut avec icônes ; marges minimales ; fenêtre sans bordure native.
- **Yazi :** Split vertical persistant à gauche (15% de l'écran) affichant l'arborescence du projet, synchronisé avec le fichier actif dans Neovim. Entièrement cliquable.
- **Neovim :** Statusline et Winbar riches (lualine, barbecue), breadcrumbs cliquables à la souris, panneau de diagnostics d'erreurs global en bas.

### 2. Le Mode Zen *(Minimaliste et Pur)*

Pensé pour le script en ligne de commande, le sysadmin, les sessions SSH, ou le code sans aucune distraction visuelle. Accessible aux utilisateurs qui souhaitent exploiter la pleine puissance du stack terminal.

**Composants activés :**
- **WezTerm :** Masquage complet de la barre d'onglets. L'écran devient une matrice de texte pure.
- **Yazi :** Le split gauche est masqué/fermé instantanément pour libérer 100% de la largeur de l'écran.
- **Neovim :** Disparition de l'arbre de fichiers. La statusline devient minimale. La recherche et l'ouverture de fichiers se font via un fuzzy finder (Snacks.picker ou Telescope).

---

## 🧠 Mécaniques Clés à Implémenter

### Le Leader Unifié (Space)

La touche Espace intercepte les commandes au niveau global. Le système détermine intelligemment si l'action concerne la structure de la fenêtre (WezTerm) ou l'édition (Neovim).

La navigation aux touches de direction (HJKL) doit traverser de manière transparente la frontière entre le panneau Yazi (WezTerm) et les buffers Neovim.

> ⚠️ **Point critique :** La stratégie de détection du focus (WezTerm vs Neovim) doit être documentée précisément. Une variable d'état partagée ou un mode tracking via le titre du pane est recommandé pour éviter les conflits d'interception.

### Communication Inter-Processus (IPC)

La communication bidirectionnelle entre Yazi et Neovim est le point le plus sensible de l'architecture. Les cas d'erreur suivants doivent être anticipés :

- Socket Neovim non encore disponible au démarrage
- Plusieurs instances Neovim actives simultanément
- Déconnexion temporaire lors d'une session SSH

**Yazi → Neovim :** Un clic ou un appui sur Entrée dans Yazi utilise les sockets RPC de Neovim (`nvim --server`) pour lui ordonner d'ouvrir le fichier sélectionné dans le panneau principal.

**Neovim → Yazi :** Le hook `BufEnter` de Neovim envoie un signal CLI à Yazi (`ya emit cd`) pour synchroniser automatiquement l'arborescence de gauche lors des changements de buffers.

---

## 📦 Stratégie de Packaging & Distribution

- **Isolation :** Le package utilise `$NVIM_APPNAME` pour Neovim et une surcharge de `XDG_CONFIG_HOME` via un script de lancement dédié pour WezTerm, garantissant que l'installation ne vient jamais écraser les dotfiles préexistants de l'utilisateur.
- **Installation :** Une commande unique, compatible macOS, Linux et WSL.

curl -fsSL https://vide.sh/install | sh
```

- **Premier lancement :** Le Mode IDE est activé par défaut. Un tutoriel interactif optionnel guide l'utilisateur à la découverte des fonctionnalités.

---

## ⚖️ Licence

**MIT** — Favorisant l'adoption massive par la communauté open source, le partage de portions de code et l'agilité des contributions externes.

---

*Document vivant — à mettre à jour au fil des décisions d'implémentation.*
