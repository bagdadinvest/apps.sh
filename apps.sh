#!/usr/bin/env bash
# apps.sh — Fresh OS bootstrapper for your KDE Neon/Ubuntu boxes
# Features:
#   - Interactive menu (whiptail if available, text fallback) to install:
#       • Input Leap (native .deb from GitHub, dep-resolving via apt)
#       • Tailscale (Ephemeral)  — auto-installs & brings up with key
#       • Tailscale (Persistent) — auto-installs & brings up with key
#   - Idempotent: skips already-installed components
#   - Env overrides for secrets/versions/URLs
#   - Clear logging & error handling
#
# Usage:
#   chmod +x ./apps.sh && ./apps.sh
#   ./apps.sh --all
#   ./apps.sh --apps "inputleap tailscale-ephemeral"
#
# Notes:
#   - Requires sudo for package install steps
#   - Designed for Ubuntu 24.04 / KDE Neon Noble
#
set -euo pipefail

# ------------------------------
# Config (overridable via env)
# ------------------------------
: "${IL_VERSION:=3.0.2}"
: "${IL_DEB_URL:=https://github.com/input-leap/input-leap/releases/download/v${IL_VERSION}/InputLeap_${IL_VERSION}_debian12_amd64.deb}"
: "${TS_AUTHKEY_EPHEMERAL:=tskey-auth-kkZiJa4rJf11CNTRL-EQ2Svo81wPH7TtiUtFKrQHQyeS8C7GHsg}"
: "${TS_AUTHKEY_PERSISTENT:=tskey-auth-krA6r5PMML11CNTRL-cVwS38jNwoeTdTPARMMDpe1oxjrdTCFz}"

# ------------------------------
# Pretty logging
# ------------------------------
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; BLUE="\e[34m"; DIM="\e[2m"; RESET="\e[0m"
log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[-]${RESET} $*" 1>&2; }
info() { echo -e "${BLUE}[*]${RESET} $*"; }

trap 'err "An unexpected error occurred (line $LINENO). Check output above."' ERR

# ------------------------------
# Helpers
# ------------------------------
have_cmd() { command -v "$1" >/dev/null 2>&1; }
need_tools() {
  local missing=()
  for t in curl wget grep sed awk; do
    have_cmd "$t" || missing+=("$t")
  done
  if ((${#missing[@]})); then
    info "Installing prerequisites: ${missing[*]}"
    sudo apt update -y || true
    sudo apt install -y "${missing[@]}"
  fi
}

assert_apt_based() {
  if ! [ -r /etc/os-release ]; then err "/etc/os-release missing — unsupported base."; exit 1; fi
  . /etc/os-release
  case "${ID_LIKE:-$ID}" in
    *debian*|*ubuntu*) ;; 
    *) warn "Non Debian/Ubuntu base detected (${ID:-unknown}). Script may fail." ;;
  esac
}

require_sudo() {
  if ! sudo -v; then err "sudo permission required."; exit 1; fi
}

enable_service_now() {
  local unit="$1"
  if systemctl list-unit-files | grep -q "^${unit}"; then
    sudo systemctl enable --now "$unit" || warn "Failed to enable/start ${unit}."
  fi
}

# ------------------------------
# Input Leap
# ------------------------------
install_inputleap() {
  if have_cmd input-leap; then
    warn "Input Leap already installed: $(command -v input-leap)"
    return 0
  fi

  need_tools
  assert_apt_based
  require_sudo

  local deb="/tmp/$(basename "$IL_DEB_URL")"
  info "Downloading Input Leap ${IL_VERSION}..."
  wget -q --show-progress -O "$deb" "$IL_DEB_URL"

  info "Installing Input Leap via apt (resolves dependencies)..."
  sudo apt install -y "$deb" || {
    err "apt install failed for $deb"; return 1;
  }

  rm -f "$deb"
  log "Input Leap installed. Version: $(input-leap --version 2>/dev/null || echo unknown)"
}

# Optional: remove Flatpak variant to avoid confusion
remove_flatpak_inputleap() {
  if have_cmd flatpak && flatpak list --app --columns=application 2>/dev/null | grep -qi '^io.github.input_leap.input-leap$'; then
    info "Removing Flatpak Input Leap to avoid conflicts..."
    flatpak uninstall -y io.github.input_leap.input-leap || warn "Flatpak uninstall failed (non-fatal)."
  fi
}

# ------------------------------
# Tailscale (common + modes)
# ------------------------------
install_tailscale_common() {
  need_tools; assert_apt_based; require_sudo

  if ! have_cmd tailscale; then
    info "Installing Tailscale (official script)..."
    curl -fsSL https://tailscale.com/install.sh | sh || { err "Tailscale install script failed."; return 1; }
  else
    warn "Tailscale already installed: $(tailscale --version | head -n1)"
  fi

  enable_service_now tailscaled.service
}

install_tailscale_ephemeral() {
  install_tailscale_common || return 1

  if tailscale status 2>/dev/null | grep -q "Logged in as"; then
    warn "Tailscale already logged in. Skipping 'tailscale up'."
    tailscale ip -4 || true
    return 0
  fi

  info "Bringing up Tailscale (EPHEMERAL) with SSH..."
  sudo tailscale up --auth-key="${TS_AUTHKEY_EPHEMERAL}" --ephemeral --ssh && \
    log "Tailscale UP (ephemeral). IPv4: $(tailscale ip -4 | tr '\n' ' ')" || {
      err "tailscale up (ephemeral) failed."; return 1; }
}

install_tailscale_persistent() {
  install_tailscale_common || return 1

  if tailscale status 2>/dev/null | grep -q "Logged in as"; then
    warn "Tailscale already logged in. Skipping 'tailscale up'."
    tailscale ip -4 || true
    return 0
  fi

  info "Bringing up Tailscale (PERSISTENT) with SSH..."
  sudo tailscale up --auth-key="${TS_AUTHKEY_PERSISTENT}" --ssh && \
    log "Tailscale UP (persistent). IPv4: $(tailscale ip -4 | tr '\n' ' ')" || {
      err "tailscale up (persistent) failed."; return 1; }
}

# ------------------------------
# Menu / CLI
# ------------------------------
show_text_menu() {
  echo "\nChoose what to install:";
  select opt in \
    "Input Leap" \
    "Tailscale (Ephemeral)" \
    "Tailscale (Persistent)" \
    "Remove Flatpak Input Leap" \
    "All" \
    "Quit"; do
    case "$REPLY" in
      1) install_inputleap ;;
      2) install_tailscale_ephemeral ;;
      3) install_tailscale_persistent ;;
      4) remove_flatpak_inputleap ;;
      5) install_inputleap; remove_flatpak_inputleap; install_tailscale_persistent ;;
      6) exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

show_whiptail_menu() {
  local choices
  choices=$(whiptail --title "apps.sh installer" --checklist "Select components to install" 20 76 10 \
    inputleap "Input Leap (.deb from GitHub)" ON \
    tailscale-ephemeral "Tailscale (Ephemeral)" OFF \
    tailscale-persistent "Tailscale (Persistent)" ON \
    remove-flatpak-inputleap "Remove Flatpak Input Leap" ON \
    3>&1 1>&2 2>&3) || return 1

  # Parse selections (items are quoted)
  for sel in $choices; do
    sel=${sel//\"/}
    case "$sel" in
      inputleap) install_inputleap ;;
      tailscale-ephemeral) install_tailscale_ephemeral ;;
      tailscale-persistent) install_tailscale_persistent ;;
      remove-flatpak-inputleap) remove_flatpak_inputleap ;;
    esac
  done
}

run_cli_apps_list() {
  local list=("$@")
  for item in "${list[@]}"; do
    case "$item" in
      inputleap) install_inputleap ;;
      tailscale-ephemeral) install_tailscale_ephemeral ;;
      tailscale-persistent) install_tailscale_persistent ;;
      remove-flatpak-inputleap) remove_flatpak_inputleap ;;
      *) warn "Unknown app: $item" ;;
    esac
  done
}

main() {
  # Parse simple flags
  local apps_list=""
  while (( "$#" )); do
    case "$1" in
      --all) apps_list="inputleap remove-flatpak-inputleap tailscale-persistent" ;;
      --apps) shift; apps_list="$1" ;;
      -h|--help)
        cat <<EOF
Usage: $0 [--all] [--apps "inputleap tailscale-ephemeral ..."]
Components:
  inputleap                Install Input Leap native .deb
  remove-flatpak-inputleap Remove Flatpak Input Leap if present
  tailscale-ephemeral      Install & bring up Tailscale (ephemeral key)
  tailscale-persistent     Install & bring up Tailscale (persistent key)
EOF
        exit 0 ;;
      *) warn "Unknown option: $1" ;;
    esac
    shift || true
  done

  log "apps.sh bootstrap starting..."

  if [[ -n "$apps_list" ]]; then
    # shellcheck disable=SC2206
    run_cli_apps_list ${apps_list}
    log "Done."
    exit 0
  fi

  if have_cmd whiptail; then
    show_whiptail_menu || warn "Menu cancelled."
  else
    warn "whiptail not found; falling back to text menu. Install with: sudo apt install whiptail"
    show_text_menu
  fi
  log "All selected tasks completed."
}

main "$@"
