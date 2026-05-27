#!/bin/bash
# Vide IDE Updater
# Updates repository configuration and synchronizes Neovim plugins

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Checking for Vide updates...${NC}"

# Detect installation source
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_DATA_HOME="$HOME/.local/share/vide"
REPO_DIR="$XDG_DATA_HOME/repo"

if [ -d "$SCRIPT_DIR/config" ]; then
    echo "Updating from local developer directory: $SCRIPT_DIR"
    TARGET_DIR="$SCRIPT_DIR"
elif [ -d "$REPO_DIR" ]; then
    echo "Updating from cloned installation: $REPO_DIR"
    TARGET_DIR="$REPO_DIR"
else
    echo -e "${YELLOW}Warning: Could not identify Vide installation directory. Defaulting to local repo...${NC}"
    TARGET_DIR="$SCRIPT_DIR"
fi

# Run git pull
cd "$TARGET_DIR"
if [ -d ".git" ]; then
    echo "Pulling latest changes from remote Git repository..."
    git pull
else
    echo -e "${YELLOW}Warning: No git repository detected in $TARGET_DIR. Skipping git update...${NC}"
fi

# Sync Neovim plugins headlessly
if command -v nvim &>/dev/null; then
    echo -e "${BLUE}Updating Neovim plugins...${NC}"
    export XDG_CONFIG_HOME="$HOME/.config/vide"
    export NVIM_APPNAME="vide-nvim"
    nvim --headless -c "Lazy! sync" -c "qa"
fi

echo -e "\n${GREEN}✔ Vide updated successfully!${NC}"
