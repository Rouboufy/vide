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

# Check and install dependencies
MISSING_DEPS=()
for cmd in git curl nvim; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_DEPS+=("$cmd")
    fi
done

if ! command -v zig &>/dev/null; then
    MISSING_DEPS+=("zig")
else
    ZIG_VER=$(zig version | cut -d. -f1,2)
    if [[ "$ZIG_VER" == "0.14" || "$ZIG_VER" == "0.13" || "$ZIG_VER" == "0.12" || "$ZIG_VER" == "0.11" || "$ZIG_VER" == "0.10" || "$ZIG_VER" == "0.9" ]]; then
        MISSING_DEPS+=("zig")
        echo -e "${YELLOW}Zig $ZIG_VER is too old (requires 0.15+). Will be upgraded.${NC}"
        if command -v snap &>/dev/null; then sudo snap remove zig &>/dev/null || true; fi
    fi
fi

if command -v nvim &>/dev/null; then
    NVIM_VER=$(nvim --version | head -n 1 | awk '{print $2}' | sed 's/v//')
    IFS='.' read -r major minor patch <<< "$NVIM_VER"
    if [ "$major" -eq 0 ] && [ "$minor" -lt 10 ]; then
        MISSING_DEPS+=("nvim(>=0.10.0)")
    fi
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${YELLOW}Missing dependencies: ${MISSING_DEPS[*]}${NC}"
    echo -e "${YELLOW}Warning: Installing system dependencies will require sudo privileges.${NC}"
    read -p "Would you like to install them now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        OS_NAME="$(uname -s)"
        if [ "$OS_NAME" = "Darwin" ]; then
            if ! command -v brew &>/dev/null; then
                echo -e "${RED}Homebrew is required on macOS. Please install Homebrew first.${NC}"
                exit 1
            fi
            brew install git curl neovim
        else
            if command -v apt-get &>/dev/null; then
                sudo apt-get update
                sudo apt-get install -y git curl python3
                if command -v snap &>/dev/null; then
                    sudo snap install nvim --classic || sudo apt-get install -y neovim
                else
                    sudo apt-get install -y neovim
                fi
            elif command -v pacman &>/dev/null; then
                sudo pacman -Sy --noconfirm git curl neovim python
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y git curl neovim python3
            elif command -v zypper &>/dev/null; then
                sudo zypper install -y git curl neovim python3
            else
                echo -e "${RED}Could not detect package manager. Please install dependencies manually.${NC}"
                exit 1
            fi
        fi

        if [[ " ${MISSING_DEPS[*]} " =~ " zig " ]]; then
            echo -e "${BLUE}Installing Zig (master branch) manually...${NC}"
            ARCH_NAME="$(uname -m)"
            if [ "$OS_NAME" = "Darwin" ]; then
                if [ "$ARCH_NAME" = "arm64" ]; then
                    ZIG_ARCH="aarch64-macos"
                else
                    ZIG_ARCH="x86_64-macos"
                fi
            else
                if [ "$ARCH_NAME" = "aarch64" ] || [ "$ARCH_NAME" = "arm64" ]; then
                    ZIG_ARCH="aarch64-linux"
                else
                    ZIG_ARCH="x86_64-linux"
                fi
            fi
            ZIG_URL=$(curl -s https://ziglang.org/download/index.json | python3 -c "import sys, json; print(json.load(sys.stdin)['master']['$ZIG_ARCH']['tarball'])")
            curl -fLo "/tmp/zig.tar.xz" "$ZIG_URL"
            sudo rm -rf /usr/local/zig
            sudo mkdir -p /usr/local/zig
            sudo tar -xf "/tmp/zig.tar.xz" -C /usr/local/zig --strip-components=1
            sudo ln -sfn /usr/local/zig/zig /usr/local/bin/zig
            rm "/tmp/zig.tar.xz"
        fi
        
        # Re-check basic tools after install
        for cmd in git curl zig nvim; do
            if ! command -v "$cmd" &>/dev/null; then
                echo -e "${RED}Error: Failed to install $cmd. Please install it manually.${NC}"
                exit 1
            fi
        done
    else
        echo -e "${RED}Please install dependencies manually to continue.${NC}"
        exit 1
    fi
fi

export XDG_CONFIG_HOME="$HOME/.config/vide"
export XDG_DATA_HOME="$HOME/.local/share/vide"
export XDG_STATE_HOME="$HOME/.local/state/vide"
export XDG_CACHE_HOME="$HOME/.cache/vide"

mkdir -p "$XDG_CONFIG_HOME"
mkdir -p "$XDG_DATA_HOME"
mkdir -p "$XDG_STATE_HOME"
mkdir -p "$XDG_CACHE_HOME"
mkdir -p "$HOME/.local/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/config" ]; then
    echo -e "${GREEN}Detected local repository installation...${NC}"
    SOURCE_DIR="$SCRIPT_DIR"
else
    echo -e "${GREEN}Downloading Vide from GitHub (macOS branch)...${NC}"
    REPO_DIR="$XDG_DATA_HOME/repo"
    BRANCH="macos"
    if [ -d "$REPO_DIR" ]; then
        cd "$REPO_DIR" && git fetch origin && git checkout $BRANCH --quiet && git pull origin $BRANCH --quiet
    else
        git clone -b $BRANCH --quiet https://github.com/Rouboufy/vide.git "$REPO_DIR"
    fi
    SOURCE_DIR="$REPO_DIR"
fi

# Build the Zig Binary
echo -e "${BLUE}Building Vide from source...${NC}"
cd "$SOURCE_DIR"
zig build -Doptimize=ReleaseFast

#  Link configurations and binary
echo -e "${BLUE}Linking configuration files...${NC}"
ln -sfn "$SOURCE_DIR/config/vide-nvim" "$XDG_CONFIG_HOME/vide-nvim"

ln -sfn "$SOURCE_DIR/zig-out/bin/vide" "$HOME/.local/bin/vide"
chmod +x "$SOURCE_DIR/zig-out/bin/vide"

#  Check and install JetBrainsMono Nerd Font
OS_NAME="$(uname -s)"
if [ "$OS_NAME" = "Darwin" ]; then
    FONT_DIR="$HOME/Library/Fonts"
    # Check if font is installed
    if [ ! -f "$FONT_DIR/JetBrainsMonoNerdFont-Regular.ttf" ] && [ ! -f "$FONT_DIR/JetBrains Mono Regular Nerd Font Complete.ttf" ]; then
        echo -e "${BLUE}JetBrainsMono Nerd Font not found on macOS. Downloading font...${NC}"
        TEMP_DIR=$(mktemp -d)
        curl -fLo "$TEMP_DIR/JetBrainsMono.zip" https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/JetBrainsMono.zip
        unzip -oqd "$TEMP_DIR" "$TEMP_DIR/JetBrainsMono.zip"
        cp "$TEMP_DIR"/*.ttf "$FONT_DIR/"
        rm -rf "$TEMP_DIR"
        echo -e "${GREEN}Font installed successfully on macOS!${NC}"
    else
        echo -e "${GREEN}JetBrainsMono Nerd Font is already installed on macOS.${NC}"
    fi
else
 
    if command -v fc-list &>/dev/null && ! fc-list : family | grep -iq "JetBrainsMono"; then
        echo -e "${BLUE}JetBrainsMono Nerd Font not found on Linux. Downloading font...${NC}"
        FONT_DIR="$HOME/.local/share/fonts/vide"
        mkdir -p "$FONT_DIR"
        curl -fLo "$FONT_DIR/JetBrainsMono.zip" https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/JetBrainsMono.zip
        unzip -oqd "$FONT_DIR" "$FONT_DIR/JetBrainsMono.zip"
        rm "$FONT_DIR/JetBrainsMono.zip"
        fc-cache -f "$FONT_DIR"
        echo -e "${GREEN}Font installed and cached successfully on Linux!${NC}"
    else
        echo -e "${GREEN}JetBrainsMono Nerd Font is already installed on Linux.${NC}"
    fi
fi

#Add ~/.local/bin to PATH in shell profile if missing
SHELL_PROFILES=("$HOME/.bashrc" "$HOME/.zshrc")
for profile in "${SHELL_PROFILES[@]}"; do
    if [ -f "$profile" ]; then
        if ! grep -q '\.local/bin' "$profile"; then
            echo -e "${BLUE}Adding ~/.local/bin to PATH in $profile...${NC}"
            echo -e '\n# Add local binaries to PATH\nexport PATH="$HOME/.local/bin:$PATH"' >> "$profile"
        fi
    fi
done

# Bootstrap Neovim plugins headlessly
if command -v nvim &>/dev/null; then
    echo -e "${BLUE}Pre-installing Neovim plugins and themes...${NC}"
    NVIM_APPNAME="vide-nvim" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" nvim --headless -c "Lazy! sync" -c "qa"
fi

echo -e "\n${GREEN}✔ Vide installation completed successfully!${NC}"
echo -e "To start, reopen your terminal and run: ${BLUE}vide${NC}\n"
