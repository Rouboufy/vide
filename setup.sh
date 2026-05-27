#!/bin/bash
# Vide IDE One-Command Installer
# Works on Linux and macOS

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ASCII Logo
echo -e "${BLUE}"
echo "██╗   ██╗██╗██████╗ ███████╗"
echo "██║   ██║██║██╔══██╗██╔════╝"
echo "██║   ██║██║██║  ██║█████╗  "
echo "╚██╗ ██╔╝██║██║  ██║██╔══╝  "
echo " ╚████╔╝ ██║██████╔╝███████╗"
echo "  ╚═══╝  ╚═╝╚═════╝ ╚══════╝"
echo -e "${NC}"
echo -e "Installing Vide IDE - The terminal-native developer environment...\n"

# 1. Check basic tools
for cmd in git curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Error: $cmd is required but not installed. Please install it first.${NC}"
        exit 1
    fi
done

# 2. Check Neovim version
if ! command -v nvim &>/dev/null; then
    echo -e "${YELLOW}Warning: Neovim is not installed. Vide requires Neovim >= 0.10.0.${NC}"
else
    NVIM_VER=$(nvim --version | head -n 1 | awk '{print $2}' | sed 's/v//')
    # Compare versions
    IFS='.' read -r major minor patch <<< "$NVIM_VER"
    if [ "$major" -eq 0 ] && [ "$minor" -lt 10 ]; then
        echo -e "${YELLOW}Warning: Neovim version $NVIM_VER is too old. Vide requires Neovim >= 0.10.0.${NC}"
    fi
fi

# 3. Check WezTerm and Yazi
for cmd in wezterm yazi; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${YELLOW}Warning: $cmd is not installed. You will need it to run Vide.${NC}"
    fi
done

# 4. Set paths
export XDG_CONFIG_HOME="$HOME/.config/vide"
export XDG_DATA_HOME="$HOME/.local/share/vide"
export XDG_STATE_HOME="$HOME/.local/state/vide"
export XDG_CACHE_HOME="$HOME/.cache/vide"

mkdir -p "$XDG_CONFIG_HOME"
mkdir -p "$XDG_DATA_HOME"
mkdir -p "$XDG_STATE_HOME"
mkdir -p "$XDG_CACHE_HOME"
mkdir -p "$HOME/.local/bin"

# 5. Resolve Source Directory (Local Repo vs Remote Clone)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/config" ]; then
    echo -e "${GREEN}Detected local repository installation...${NC}"
    SOURCE_DIR="$SCRIPT_DIR"
else
    echo -e "${GREEN}Downloading Vide from GitHub...${NC}"
    REPO_DIR="$XDG_DATA_HOME/repo"
    if [ -d "$REPO_DIR" ]; then
        cd "$REPO_DIR" && git pull --quiet
    else
        git clone --quiet https://github.com/Rouboufy/vide.git "$REPO_DIR"
    fi
    SOURCE_DIR="$REPO_DIR"
fi

# 6. Link configurations
echo -e "${BLUE}Linking configuration files...${NC}"
ln -sfn "$SOURCE_DIR/config/wezterm" "$XDG_CONFIG_HOME/wezterm"
ln -sfn "$SOURCE_DIR/config/vide-nvim" "$XDG_CONFIG_HOME/vide-nvim"
ln -sfn "$SOURCE_DIR/config/yazi" "$XDG_CONFIG_HOME/yazi"

# 7. Symlink wrapper launcher binary
ln -sfn "$SOURCE_DIR/bin/vide" "$HOME/.local/bin/vide"
chmod +x "$SOURCE_DIR/bin/vide"
chmod +x "$SOURCE_DIR/bin/vide-open"

# 8. Check and install JetBrainsMono Nerd Font
if command -v fc-list &>/dev/null && ! fc-list : family | grep -iq "JetBrainsMono"; then
    echo -e "${BLUE}JetBrainsMono Nerd Font not found. Downloading font...${NC}"
    FONT_DIR="$HOME/.local/share/fonts/vide"
    mkdir -p "$FONT_DIR"
    curl -fLo "$FONT_DIR/JetBrainsMono.zip" https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/JetBrainsMono.zip
    unzip -oqd "$FONT_DIR" "$FONT_DIR/JetBrainsMono.zip"
    rm "$FONT_DIR/JetBrainsMono.zip"
    fc-cache -f "$FONT_DIR"
    echo -e "${GREEN}Font installed and cached successfully!${NC}"
fi

# 9. Add ~/.local/bin to PATH in shell profile if missing
SHELL_PROFILES=("$HOME/.bashrc" "$HOME/.zshrc")
for profile in "${SHELL_PROFILES[@]}"; do
    if [ -f "$profile" ]; then
        if ! grep -q '\.local/bin' "$profile"; then
            echo -e "${BLUE}Adding ~/.local/bin to PATH in $profile...${NC}"
            echo -e '\n# Add local binaries to PATH\nexport PATH="$HOME/.local/bin:$PATH"' >> "$profile"
        fi
    fi
done

# 10. Bootstrap Neovim plugins headlessly
if command -v nvim &>/dev/null; then
    echo -e "${BLUE}Pre-installing Neovim plugins and themes...${NC}"
    NVIM_APPNAME="vide-nvim" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" nvim --headless -c "Lazy! sync" -c "qa"
fi

echo -e "\n${GREEN}✔ Vide installation completed successfully!${NC}"
echo -e "To start, reopen your terminal and run: ${BLUE}vide${NC}\n"
