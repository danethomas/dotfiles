#!/usr/bin/env bash
# Bootstrap a new machine with dotfiles + all tools.
#
# Usage (one-liner from a fresh box):
#   bash <(curl -fsSL https://raw.githubusercontent.com/danethomas/dotfiles/main/install.sh)
#
# Or after cloning:
#   bash ~/src/dotfiles/install.sh

set -euo pipefail

DOTFILES_REPO="danethomas/dotfiles"
WORKSPACE_REPO="danethomas/openclaw-workspace"  # separate repo for Sparky's brain

info()    { echo "▶ $*"; }
success() { echo "✓ $*"; }
warn()    { echo "⚠ $*"; }

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

# ── 4. OpenClaw workspace ─────────────────────────────────────────────────────
if [ ! -d ~/.openclaw/workspace/.git ]; then
  info "Cloning OpenClaw workspace..."
  mkdir -p ~/.openclaw
  git clone "https://github.com/$WORKSPACE_REPO.git" ~/.openclaw/workspace
  success "Workspace cloned"
else
  warn "Workspace already exists — pull manually if needed: git -C ~/.openclaw/workspace pull"
fi

# ── 5. Final steps ────────────────────────────────────────────────────────────
success "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Sign in to 1Password CLI:  op signin"
echo "  2. Start OpenClaw:            openclaw gateway start"
echo "  3. Connect to Tailscale:      sudo tailscale up"
