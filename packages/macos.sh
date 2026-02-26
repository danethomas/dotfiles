#!/usr/bin/env bash
# Install all CLI tools on macOS (Apple Silicon or Intel).
# Idempotent — safe to re-run.

set -euo pipefail

info()    { echo "  ▶ $*"; }
success() { echo "  ✓ $*"; }

# ── Homebrew ──────────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add to PATH for this session
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  success "Homebrew installed"
else
  success "Homebrew already installed ($(brew --version | head -1))"
fi

# Ensure brew is in PATH
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ── Base tools ────────────────────────────────────────────────────────────────
for pkg in git curl jq; do
  if ! command -v "$pkg" &>/dev/null; then
    brew install "$pkg"
    success "$pkg installed"
  else
    success "$pkg already installed"
  fi
done

# ── Node.js ───────────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  info "Installing Node.js..."
  brew install node
  success "Node.js installed"
else
  success "Node.js already installed ($(node -v))"
fi

# ── Bun ───────────────────────────────────────────────────────────────────────
if ! command -v bun &>/dev/null; then
  info "Installing Bun..."
  curl -fsSL https://bun.sh/install | bash
  success "Bun installed"
else
  success "Bun already installed ($(bun --version))"
fi

# ── GitHub CLI ────────────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  info "Installing GitHub CLI..."
  brew install gh
  success "GitHub CLI installed"
else
  success "gh already installed ($(gh --version | head -1))"
fi

# ── Tailscale ─────────────────────────────────────────────────────────────────
if ! command -v tailscale &>/dev/null; then
  info "Installing Tailscale..."
  brew install tailscale
  success "Tailscale installed"
else
  success "Tailscale already installed"
fi

# ── 1Password CLI ─────────────────────────────────────────────────────────────
if ! command -v op &>/dev/null; then
  info "Installing 1Password CLI..."
  brew install --cask 1password-cli
  success "1Password CLI installed"
else
  success "op already installed ($(op --version))"
fi

# ── Docker Desktop ────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  info "Installing Docker Desktop..."
  brew install --cask docker
  success "Docker Desktop installed (launch it once to complete setup)"
else
  success "Docker already installed ($(docker --version))"
fi

# ── OpenClaw ──────────────────────────────────────────────────────────────────
if ! command -v openclaw &>/dev/null; then
  info "Installing OpenClaw..."
  npm install -g openclaw
  success "OpenClaw installed"
else
  success "OpenClaw already installed ($(openclaw --version 2>/dev/null || echo 'version unknown'))"
fi

# ── gog (Google Workspace CLI) ────────────────────────────────────────────────
if ! command -v gog &>/dev/null; then
  info "Installing gog..."
  brew install steipete/tap/gogcli
  success "gog installed"
else
  success "gog already installed ($(gog --version 2>/dev/null || echo 'version unknown'))"
fi

# ── Fix npm global dir ownership ──────────────────────────────────────────────
NPM_PREFIX=$(npm config get prefix)
info "Fixing npm global dir ownership ($NPM_PREFIX)..."
sudo chown -R "$USER":"admin" "$NPM_PREFIX" 2>/dev/null || true
success "npm global dir owned by $USER"
