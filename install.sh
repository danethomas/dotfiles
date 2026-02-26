#!/usr/bin/env bash
# Bootstrap a new machine with dotfiles + all tools.
#
# Usage (one-liner from a fresh box):
#   bash <(curl -fsSL https://raw.githubusercontent.com/danethomas/dotfiles/main/install.sh)
#
# Or after cloning:
#   bash ~/src/dotfiles/install.sh
#
# Prerequisites:
#   - 1Password CLI signed in: op signin
#   - See docs/1password-setup.md for required vault items

set -euo pipefail

DOTFILES_REPO="danethomas/dotfiles"
WORKSPACE_REPO="danethomas/sparky"
GIT_EMAIL="dane@danethomas.net"

info()    { echo "▶ $*"; }
success() { echo "✓ $*"; }
warn()    { echo "⚠ $*"; }

# ── 0. Check 1Password is signed in ──────────────────────────────────────────
if ! op whoami &>/dev/null; then
  echo "❌ 1Password CLI not signed in. Run: op signin"
  exit 1
fi
success "1Password CLI authenticated"

# ── 1. Package dependencies ───────────────────────────────────────────────────
info "Installing system packages..."
bash "$(dirname "$0")/packages/ubuntu.sh"

# ── 2. chezmoi ────────────────────────────────────────────────────────────────
if ! command -v chezmoi &>/dev/null; then
  info "Installing chezmoi..."
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
  success "chezmoi installed"
else
  success "chezmoi already installed"
fi

# ── 3. Apply dotfiles (pulls secrets from 1Password) ─────────────────────────
info "Applying dotfiles via chezmoi..."
if [ -d ~/.local/share/chezmoi/.git ]; then
  chezmoi update --apply
else
  chezmoi init --apply "$DOTFILES_REPO"
fi
success "Dotfiles applied"

# ── 4. SSH key ────────────────────────────────────────────────────────────────
if [ ! -f ~/.ssh/id_ed25519 ]; then
  info "Generating SSH key..."
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f ~/.ssh/id_ed25519 -N ""
  success "SSH key generated: ~/.ssh/id_ed25519"
  info "Adding SSH key to GitHub..."
  gh auth login --with-token <<< "$(op read 'op://Private/GitHub PAT (openclaw)/credential')"
  gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)-$(date +%Y%m%d)"
  success "SSH key added to GitHub"
else
  success "SSH key already exists"
fi

# ── 5. GitHub CLI auth ────────────────────────────────────────────────────────
if ! gh auth status &>/dev/null; then
  info "Authenticating GitHub CLI..."
  gh auth login --with-token <<< "$(op read 'op://Private/GitHub PAT (openclaw)/credential')"
  success "GitHub CLI authenticated"
else
  success "GitHub CLI already authenticated"
fi

# ── 6. Tailscale ─────────────────────────────────────────────────────────────
if ! tailscale status &>/dev/null 2>&1; then
  info "Connecting to Tailscale..."
  sudo tailscale up --authkey "$(op read 'op://Private/Tailscale Auth Key/credential')"
  success "Tailscale connected"
else
  success "Tailscale already connected"
fi

# ── 7. OpenClaw workspace ─────────────────────────────────────────────────────
if [ ! -d ~/.openclaw/workspace/.git ]; then
  info "Cloning OpenClaw workspace (sparky)..."
  mkdir -p ~/.openclaw
  git clone "https://github.com/$WORKSPACE_REPO.git" ~/.openclaw/workspace
  success "Workspace cloned"
else
  warn "Workspace already exists — pull manually if needed: git -C ~/.openclaw/workspace pull"
fi

# ── 8. src/ directory ────────────────────────────────────────────────────────
mkdir -p ~/src
success "~/src ready"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "✅ Setup complete!"
echo ""
echo "Remaining manual steps:"
echo "  1. openclaw gateway start"
echo "  2. Copy ~/.openclaw/openclaw.json from old machine (or 1Password secure note)"
echo "  3. docker: re-login or run 'newgrp docker' to use without sudo"
