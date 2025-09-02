# apps.sh#!/usr/bin/env bash
# bootstrap.sh – extensible bootstrap installer
# Usage: ./bootstrap.sh

set -euo pipefail

# Colors
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# Log function
log() { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err() { echo -e "${RED}[-]${RESET} $*"; }

# === Functions for apps ===

install_inputleap() {
    if command -v input-leap >/dev/null 2>&1; then
        warn "Input Leap is already installed."
        return
    fi
    log "Installing Input Leap..."
    tmpfile="/tmp/InputLeap_3.0.2_debian12_amd64.deb"
    wget -q --show-progress -O "$tmpfile" \
      "https://github.com/input-leap/input-leap/releases/download/v3.0.2/InputLeap_3.0.2_debian12_amd64.deb"
    sudo apt install -y "$tmpfile"
    rm -f "$tmpfile"
    log "Input Leap installed."
}

# === Menu system ===

show_menu() {
    echo "Select apps to install (space = select, enter = confirm):"
    options=("Input Leap" "All" "Quit")
    select opt in "${options[@]}"; do
        case $opt in
            "Input Leap") install_inputleap ;;
            "All") install_inputleap ;;
            "Quit") exit 0 ;;
            *) warn "Invalid option" ;;
        esac
    done
}

# === Main ===

if [[ $EUID -eq 0 ]]; then
    err "Do not run as root. Use your normal user."
    exit 1
fi

log "Starting bootstrap..."
show_menu
