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
  success "Tailscale installed"
else
  success "Tailscale already installed"
fi

# ── 1Password CLI ─────────────────────────────────────────────────────────────
if ! command -v op &>/dev/null; then
  info "Installing 1Password CLI..."
  ARCH=$(dpkg --print-architecture)
  curl -fsSL "https://downloads.1password.com/linux/debian/${ARCH}/stable/1password-cli-${ARCH}-latest.deb" \
    -o /tmp/op.deb
  sudo dpkg -i /tmp/op.deb && rm /tmp/op.deb
  success "1Password CLI installed"
else
  success "op already installed ($(op --version))"
fi

# ── Docker (for devcontainers) ────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  info "Installing Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq  # must refresh after adding Docker repo
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  success "Docker installed (re-login or 'newgrp docker' to use without sudo)"
else
  success "Docker already installed ($(docker --version))"
fi

# ── OpenClaw ──────────────────────────────────────────────────────────────────
if ! command -v openclaw &>/dev/null; then
  info "Installing OpenClaw..."
  sudo npm install -g openclaw
  success "OpenClaw installed"
else
  success "OpenClaw already installed ($(openclaw --version 2>/dev/null || echo 'version unknown'))"
fi

# ── Homebrew ──────────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  info "Installing Homebrew..."
  sudo mkdir -p /home/linuxbrew/.linuxbrew
  sudo chown -R "$USER" /home/linuxbrew/.linuxbrew
  NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for this session
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  success "Homebrew installed"
else
  success "Homebrew already installed"
fi

# Ensure brew is in PATH
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true

# ── gog (Google Workspace CLI) ────────────────────────────────────────────────
if ! command -v gog &>/dev/null; then
  info "Installing gog..."
  brew install steipete/tap/gogcli
  success "gog installed"
else
  success "gog already installed ($(gog --version 2>/dev/null || echo 'version unknown'))"
fi
