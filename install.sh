#!/bin/bash
# ============================================================================
# MV Maestro - Installation Script
# made with love by @drdeeks
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  MV Maestro — Installer                       ║${NC}"
echo -e "${BLUE}║  made with love by @drdeeks                   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# Detect installation directory
INSTALL_DIR="${1:-$HOME/bash-enhanced-system}"

echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

# Check bash version
if [[ $(bash --version | head -1 | grep -o '[0-9]\+\.[0-9]\+' | cut -d. -f1) -lt 4 ]]; then
    echo -e "${RED}✗ Error: Bash 4.0+ required${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Bash $(bash --version | head -1 | cut -d')' -f2)"

# Check Python for TUI
if command -v python3 >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Python 3 available"
else
    echo -e "  ${YELLOW}⚠${NC} Python 3 not found (TUI menu unavailable)"
fi

# Check fzf for enhanced features
if command -v fzf >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} fzf available"
else
    echo -e "  ${YELLOW}⚠${NC} fzf not found (fuzzy search unavailable)"
fi

echo ""
echo -e "${YELLOW}[2/5] Creating installation directory...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/modules"
mkdir -p "$INSTALL_DIR/tests"
mkdir -p "$INSTALL_DIR/docs"

echo -e "  ${GREEN}✓${NC} Created $INSTALL_DIR"

echo ""
echo -e "${YELLOW}[3/5] Copying files...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "$SCRIPT_DIR/bash_enhanced.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/menu_tui.py" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/docker_tui.py" "$INSTALL_DIR/" 2>/dev/null || true

cp "$SCRIPT_DIR/modules/"*.sh "$INSTALL_DIR/modules/"
cp "$SCRIPT_DIR/tests/validate_menu.sh" "$INSTALL_DIR/tests/" 2>/dev/null || true
cp "$SCRIPT_DIR/docs/"* "$INSTALL_DIR/docs/" 2>/dev/null || true

echo -e "  ${GREEN}✓${NC} Files copied successfully"

echo ""
echo -e "${YELLOW}[4/5] Setting permissions...${NC}"
chmod +x "$INSTALL_DIR/bash_enhanced.sh"
chmod +x "$INSTALL_DIR/modules/"*.sh
chmod +x "$INSTALL_DIR/tests/validate_menu.sh" 2>/dev/null || true

echo -e "  ${GREEN}✓${NC} Permissions set"

echo ""
echo -e "${YELLOW}[5/5] Configuring shell...${NC}"

# Check if already configured
if grep -q "bash-enhanced-system" ~/.bashrc 2>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC} Already configured in ~/.bashrc"
    read -p "  Reconfigure? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "  ${YELLOW}⚠${NC} Skipping configuration"
    else
        # Remove old config
        sed -i '/bash-enhanced-system/d' ~/.bashrc
    fi
fi

# Add to .bashrc
cat >> ~/.bashrc << BASHRC

# ─────────────────────────────────────────────────────────────────────────────
# MV Maestro - System Identity
# made with love by @drdeeks
# ─────────────────────────────────────────────────────────────────────────────
export MV_MAESTRO_HOME="$INSTALL_DIR"
source "$INSTALL_DIR/bash_enhanced.sh"
BASHRC

echo -e "  ${GREEN}✓${NC} Added to ~/.bashrc"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation Complete!                     ║${NC}"
echo -e "${GREEN}║  made with love by @drdeeks                 ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "To activate, run:"
echo -e "  ${BLUE}source ~/.bashrc${NC}"
echo ""
echo -e "Or open a new terminal."
echo ""
echo -e "Quick commands:"
echo -e "  ${CYAN}dm${NC}              - Interactive menu"
echo -e "  ${CYAN}mvhelp${NC}          - Command reference"
echo -e "  ${CYAN}dynhelp${NC}         - Dynamic commands"
echo -e "  ${CYAN}ssh-profile-setup${NC} - SSH wizard"
echo ""

# Optional: Install additional tools
echo -e "${YELLOW}Optional dependencies:${NC}"
echo "  pip install textual     # For TUI menu"
echo "  sudo apt install fzf    # For fuzzy search"
echo "  age                     # For modern encryption"
echo "  gpg                     # For traditional encryption"
echo ""

exit 0
