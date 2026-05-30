#!/bin/bash
# Vide IDE Cleaner / Uninstaller
# Cleans up Vide sandbox directories and wrappers

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Prompt confirmation
echo -e "${YELLOW}Warning: This will remove all Vide configurations, plugins, and logs.${NC}"
read -p "Are you sure you want to uninstall Vide? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo -e "${BLUE}Uninstalling Vide...${NC}"

# Remove config and sandbox paths
paths=(
    "$HOME/.config/vide"
    "$HOME/.local/share/vide"
    "$HOME/.local/state/vide"
    "$HOME/.cache/vide"
    "$HOME/.local/bin/vide"
    "$HOME/.local/bin/vide-open"
    "$HOME/.local/bin/vide-sidebar"
    "$HOME/.local/bin/vide-activity-bar"
    "$HOME/.local/bin/vide-search-fzf"
)

for p in "${paths[@]}"; do
    if [ -e "$p" ] || [ -L "$p" ]; then
        echo "Removing $p..."
        rm -rf "$p"
    fi
done

echo -e "\n${GREEN}✔ Vide has been completely uninstalled.${NC}"
