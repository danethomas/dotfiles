#!/usr/bin/env bash
# Install all CLI tools on Ubuntu/Debian ARM64 (or x86).
# Idempotent — safe to re-run.

set -euo pipefail

info()    { echo "  ▶ $*"; }
success() { echo "  ✓ $*"; }

APT_UPDATED=false
apt_update() {
  if [ "$APT_UPDATED" = false ]; then
    sudo apt-get update -qq
    APT_UPDATED=true
  fi
}

apt_install() {
  if ! dpkg -s "$1" &>/dev/null; then
    apt_update
    sudo apt-get install -y --no-install-recommends "$1"
    success "$1 installed"
  else
    success "$1 already installed"
  fi
}

# ── Base tools ────────────────────────────────────────────────────────────────
for pkg in curl git unzip jq; do
  apt_install "$pkg"
done

# ── Node.js (via NodeSource) ──────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  info "Installing Node.js 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
  sudo apt-get install -y nodejs
  success "Node.js installed"
else
  success "Node.js already installed ($(node -v))"
fi

# ── Bun ───────────────────────────────────────────────────────────────────────
if ! command -v bun &>/dev/null; then
  info "Installing Bun..."
  curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash -
  success "Bun installed"
else
  success "Bun already installed ($(bun --version))"
fi

# ── GitHub CLI ────────────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  info "Installing GitHub CLI..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  apt_update
  sudo apt-get install -y gh
  success "GitHub CLI installed"
else
  success "gh already installed ($(gh --version | head -1))"
fi

# ── Tailscale ─────────────────────────────────────────────────────────────────
if ! command -v tailscale &>/dev/null; then
  info "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  success "Tailscale installed (run: sudo tailscale up)"
else
  success "Tailscale already installed"
fi

# ── 1Password CLI ─────────────────────────────────────────────────────────────
if ! command -v op &>/dev/null; then
  info "Installing 1Password CLI..."
  curl -fsSL https://downloads.1password.com/linux/debian/amd64/stable/1password-cli-amd64-latest.deb \
    -o /tmp/op.deb
  # ARM64 override
  ARCH=$(dpkg --print-architecture)
  if [ "$ARCH" = "arm64" ]; then
    curl -fsSL https://downloads.1password.com/linux/debian/arm64/stable/1password-cli-arm64-latest.deb \
      -o /tmp/op.deb
  fi
  sudo dpkg -i /tmp/op.deb && rm /tmp/op.deb
  success "1Password CLI installed"
else
  success "op already installed ($(op --version))"
fi

# ── OpenClaw ──────────────────────────────────────────────────────────────────
if ! command -v openclaw &>/dev/null; then
  info "Installing OpenClaw..."
  sudo npm install -g openclaw
  success "OpenClaw installed"
else
  success "OpenClaw already installed ($(openclaw --version 2>/dev/null || echo 'version unknown'))"
fi
