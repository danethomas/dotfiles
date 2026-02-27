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

# ── 1. Package dependencies ───────────────────────────────────────────────────
info "Installing system packages..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/packages"

# If running via curl pipe, packages/ won't exist — clone chezmoi repo first
if [ ! -d "$PACKAGES_DIR" ]; then
  info "Fetching dotfiles repo for packages..."
  if [ ! -d "$HOME/.local/share/chezmoi/.git" ]; then
    mkdir -p "$HOME/.local/share/chezmoi"
    # Use curl to fetch packages without triggering Xcode git stub on macOS
    for f in packages/macos.sh packages/ubuntu.sh; do
      mkdir -p "$HOME/.local/share/chezmoi/$(dirname $f)"
      curl -fsSL "https://raw.githubusercontent.com/$DOTFILES_REPO/main/$f" \
        -o "$HOME/.local/share/chezmoi/$f"
    done
  fi
  PACKAGES_DIR="$HOME/.local/share/chezmoi/packages"
  SCRIPT_DIR="$HOME/.local/share/chezmoi"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  bash "$PACKAGES_DIR/macos.sh"
else
  bash "$PACKAGES_DIR/ubuntu.sh"
fi

# ── 1a. Fix PATH for login shells ────────────────────────────────────────────
# SSH login shells source ~/.profile, not ~/.bashrc. Make ~/.profile source
# ~/.bashrc so npm-global/bin and other PATH additions are always available.
if ! grep -q '\.bashrc' ~/.profile 2>/dev/null; then
  cat >> ~/.profile << 'PROFILE_EOF'

# Source .bashrc for interactive login shells (ensures PATH is consistent)
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
PROFILE_EOF
  success "~/.profile configured to source ~/.bashrc"
fi

# ── 2. 1Password sign-in ──────────────────────────────────────────────────────
if ! op whoami &>/dev/null; then
  echo ""
  echo "🔐 1Password CLI needs signing in before we can continue."
  echo "   Run: op signin"
  echo "   Then re-run this script — it's idempotent, will skip what's done."
  exit 0
fi
success "1Password CLI authenticated ($(op whoami --format=json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("email",""))' 2>/dev/null || echo 'signed in'))"

# ── 3. chezmoi ────────────────────────────────────────────────────────────────
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
else
  success "SSH key already exists"
fi

# ── 5. GitHub CLI auth ────────────────────────────────────────────────────────
if ! gh auth status &>/dev/null; then
  info "Authenticating GitHub CLI..."
  gh auth login --with-token <<< "$(op read 'op://Keys/GitHub PAT openclaw/credential')"
  success "GitHub CLI authenticated"
else
  success "GitHub CLI already authenticated"
fi

# ── 5a. Upload SSH key to GitHub (always attempt — idempotent) ────────────────
info "Uploading SSH key to GitHub..."
if gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)-$(date +%Y%m%d)"; then
  success "SSH key uploaded to GitHub"
else
  warn "SSH key upload failed — add manually at https://github.com/settings/ssh/new"
  warn "$(cat ~/.ssh/id_ed25519.pub)"
fi

# ── 6. Tailscale ─────────────────────────────────────────────────────────────
if ! tailscale status &>/dev/null 2>&1; then
  info "Connecting to Tailscale..."
  sudo tailscale up --authkey "$(op read 'op://Keys/Tailscale Auth Key/credential')"
  success "Tailscale connected"
else
  success "Tailscale already connected"
fi

# Allow non-root tailscale serve (Linux only — Mac doesn't need this)
if [[ "$OSTYPE" != "darwin"* ]]; then
  info "Setting Tailscale operator to $USER..."
  sudo tailscale set --operator="$USER"
  success "Tailscale operator set"
fi

# ── 7. OpenClaw workspace ─────────────────────────────────────────────────────
if [ ! -d ~/.openclaw/workspace/.git ]; then
  info "Cloning OpenClaw workspace (sparky)..."
  mkdir -p ~/.openclaw
  rm -rf ~/.openclaw/workspace  # remove partial clone if present
  git clone "git@github.com:$WORKSPACE_REPO.git" ~/.openclaw/workspace
  success "Workspace cloned"
else
  warn "Workspace already exists — pull manually if needed: git -C ~/.openclaw/workspace pull"
fi

# ── 8. Restore OpenClaw config snapshots (cron jobs, hooks, exec-approvals) ──
SNAPSHOTS=~/.openclaw/workspace/config-snapshots
if [ -d "$SNAPSHOTS" ]; then
  info "Restoring OpenClaw config snapshots..."
  mkdir -p ~/.openclaw/cron ~/.openclaw/hooks/transforms
  [ -f "$SNAPSHOTS/cron-jobs.json" ]   && cp "$SNAPSHOTS/cron-jobs.json" ~/.openclaw/cron/jobs.json
  [ -d "$SNAPSHOTS/hooks-transforms" ] && cp -r "$SNAPSHOTS/hooks-transforms/." ~/.openclaw/hooks/transforms/
  [ -f "$SNAPSHOTS/exec-approvals.json" ] && cp "$SNAPSHOTS/exec-approvals.json" ~/.openclaw/exec-approvals.json
  success "Config snapshots restored"
fi

# ── 9. Restore credentials from 1Password ────────────────────────────────────
info "Restoring OpenClaw credentials from 1Password..."
bash ~/.openclaw/workspace/scripts/import-credentials-from-1password.sh

# ── 10. src/ directory + shaping-skills ──────────────────────────────────────
mkdir -p ~/src
success "~/src ready"

if [ ! -d ~/src/shaping-skills/.git ]; then
  info "Cloning shaping-skills..."
  git clone https://github.com/rjs/shaping-skills.git ~/src/shaping-skills
  success "shaping-skills cloned"
else
  success "shaping-skills already present"
fi

# ── 11. Claude Code auth (ANTHROPIC_API_KEY from 1Password) ──────────────────
if command -v claude &>/dev/null; then
  info "Configuring Claude Code auth from 1Password..."
  ANTHROPIC_API_KEY=$(op item get "Claude Code oAuth Key" --reveal --fields credential 2>/dev/null || echo "")
  if [ -n "$ANTHROPIC_API_KEY" ]; then
    # Add to ~/.bashrc if not already there
    if ! grep -q "ANTHROPIC_API_KEY" "$HOME/.bashrc" 2>/dev/null; then
      echo "export ANTHROPIC_API_KEY=\"$ANTHROPIC_API_KEY\"" >> "$HOME/.bashrc"
    fi
    export ANTHROPIC_API_KEY
    success "ANTHROPIC_API_KEY set from 1Password"
  else
    warn "Could not fetch Claude Code key from 1Password — run 'op signin' first"
  fi
fi

# ── 12. Install + start OpenClaw gateway service ─────────────────────────────
info "Installing OpenClaw gateway service..."
openclaw gateway install
success "Gateway service installed"



# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "✅ Setup complete!"
echo ""
echo "Remaining manual steps:"
echo "  1. openclaw gateway start"
echo "  2. Copy ~/.openclaw/openclaw.json from old machine"
echo "  3. Clone your dev repos into ~/src/"
echo ""

# Refresh docker group membership so docker works without sudo immediately
if groups "$USER" 2>/dev/null | grep -q docker || id -nG 2>/dev/null | grep -q docker; then
  echo "↻ Refreshing Docker group membership..."
  exec newgrp docker
fi
