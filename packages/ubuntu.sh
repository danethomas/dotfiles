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

# ── npm global prefix (user-owned, avoids /usr/bin permission issues) ─────────
if [ "$(npm config get prefix)" != "$HOME/.npm-global" ]; then
  info "Setting npm global prefix to ~/.npm-global..."
  npm config set prefix "$HOME/.npm-global"
  mkdir -p "$HOME/.npm-global/bin"
  # Add to PATH if not already there
  if ! grep -q '.npm-global/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
  fi
  export PATH="$HOME/.npm-global/bin:$PATH"
  success "npm prefix set to ~/.npm-global"
fi

# ── Claude Code ───────────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
  info "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
  success "Claude Code installed"
else
  success "Claude Code already installed ($(claude --version 2>/dev/null | head -1))"
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
  info "Installing gog (linux_arm64 binary)..."
  GOG_VERSION=$(curl -s https://api.github.com/repos/steipete/gogcli/releases/latest | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])")
  GOG_URL="https://github.com/steipete/gogcli/releases/download/${GOG_VERSION}/gogcli_${GOG_VERSION#v}_linux_arm64.tar.gz"
  curl -fsSL "$GOG_URL" -o /tmp/gogcli.tar.gz
  sudo tar -xzf /tmp/gogcli.tar.gz -C /usr/local/bin gog
  rm /tmp/gogcli.tar.gz
  success "gog installed ($GOG_VERSION)"
else
  success "gog already installed ($(gog --version 2>/dev/null || echo 'version unknown'))"
fi
