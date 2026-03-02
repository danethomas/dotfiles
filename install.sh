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
if ! grep -q '\.bashrc' ~/.bash_profile 2>/dev/null; then
  cat >> ~/.bash_profile << 'PROFILE_EOF'

# Source .bashrc for interactive login shells (ensures PATH is consistent)
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
PROFILE_EOF
  success "~/.bash_profile configured to source ~/.bashrc"
fi

# ── 2. 1Password Service Account Token ───────────────────────────────────────
# Service token allows non-interactive op access (no op signin needed).
# Store in 1Password manually as "1Password Service Token - Sparky" in Keys vault.
if ! grep -q "OP_SERVICE_ACCOUNT_TOKEN" "$HOME/.bashrc" 2>/dev/null; then
  echo ""
  echo "🔑 1Password Service Account Token needed for non-interactive access."
  echo "   Find it in 1Password → Keys → '1Password Service Token - Sparky'"
  echo -n "   Paste token (or press Enter to skip): "
  read -r OP_TOKEN
  if [ -n "$OP_TOKEN" ]; then
    echo "export OP_SERVICE_ACCOUNT_TOKEN="$OP_TOKEN"" >> "$HOME/.bashrc"
    export OP_SERVICE_ACCOUNT_TOKEN="$OP_TOKEN"
    success "OP_SERVICE_ACCOUNT_TOKEN added to ~/.bashrc"
  else
    warn "Skipped — some credential steps may require manual op signin"
  fi
else
  export OP_SERVICE_ACCOUNT_TOKEN="$(grep OP_SERVICE_ACCOUNT_TOKEN "$HOME/.bashrc" | sed 's/export OP_SERVICE_ACCOUNT_TOKEN="//;s/"//')"
  success "OP_SERVICE_ACCOUNT_TOKEN already set"
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
SNAPSHOTS=~/.openclaw/workspace/scripts/openclaw
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

# ── 11a. Obsidian auth token from 1Password ───────────────────────────────────
if command -v ob &>/dev/null; then
  info "Configuring Obsidian auth token from 1Password..."
  OBSIDIAN_AUTH_TOKEN=$(op item get "Obsidian Auth Token" --reveal --fields credential 2>/dev/null || echo "")
  OBSIDIAN_VAULT_PASSWORD=$(op item get "Obsidian Vault Password" --reveal --fields credential 2>/dev/null || echo "")
  if [ -n "$OBSIDIAN_AUTH_TOKEN" ]; then
    if ! grep -q "OBSIDIAN_AUTH_TOKEN" "$HOME/.bashrc" 2>/dev/null; then
      echo "export OBSIDIAN_AUTH_TOKEN=\"$OBSIDIAN_AUTH_TOKEN\"" >> "$HOME/.bashrc"
    fi
    if [ -n "$OBSIDIAN_VAULT_PASSWORD" ] && ! grep -q "OBSIDIAN_VAULT_PASSWORD" "$HOME/.bashrc" 2>/dev/null; then
      echo "export OBSIDIAN_VAULT_PASSWORD=\"$OBSIDIAN_VAULT_PASSWORD\"" >> "$HOME/.bashrc"
    fi
    export OBSIDIAN_AUTH_TOKEN OBSIDIAN_VAULT_PASSWORD
    # Write clean env file for systemd (can't source .bashrc directly)
    echo "OBSIDIAN_AUTH_TOKEN=$OBSIDIAN_AUTH_TOKEN" > "$HOME/.config/obsidian-sync.env"
    chmod 600 "$HOME/.config/obsidian-sync.env"
    success "OBSIDIAN_AUTH_TOKEN + OBSIDIAN_VAULT_PASSWORD set from 1Password"
  else
    warn "Could not fetch Obsidian auth token from 1Password — add it manually"
  fi
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

# ── 12. Obsidian Sync setup ───────────────────────────────────────────────────
if command -v ob &>/dev/null && [ -n "${OBSIDIAN_AUTH_TOKEN:-}" ]; then
  VAULT_ROOT=~/.openclaw/workspace
  WORKSPACE="$VAULT_ROOT"
  if [ ! -f "$VAULT_ROOT/.obsidian-sync" ]; then
    info "Setting up Obsidian Sync for workspace vault..."
    OB_CMD="dbus-run-session -- bash -c 'eval \$(echo \"\" | gnome-keyring-daemon --unlock --components=secrets,pkcs11,ssh --daemonize 2>/dev/null); export GNOME_KEYRING_CONTROL GNOME_KEYRING_PID; ob"

    # Setup vault (uses OBSIDIAN_VAULT_PASSWORD env var if set)
    VAULT_PASSWORD_FLAG=""
    [ -n "${OBSIDIAN_VAULT_PASSWORD:-}" ] && VAULT_PASSWORD_FLAG="--password \"$OBSIDIAN_VAULT_PASSWORD\""
    eval "dbus-run-session -- bash -c 'eval \$(echo \"\" | gnome-keyring-daemon --unlock --components=secrets,pkcs11,ssh --daemonize 2>/dev/null); export GNOME_KEYRING_CONTROL GNOME_KEYRING_PID; ob sync-setup --vault \"Sparky\" --path $WORKSPACE --device-name \"\$(hostname)\" $VAULT_PASSWORD_FLAG'" \
      && touch "$VAULT_ROOT/.obsidian-sync" \
      && success "Obsidian vault configured"

    # Configure exclusions
    eval "dbus-run-session -- bash -c 'eval \$(echo \"\" | gnome-keyring-daemon --unlock --components=secrets,pkcs11,ssh --daemonize 2>/dev/null); export GNOME_KEYRING_CONTROL GNOME_KEYRING_PID; ob sync-config --path $WORKSPACE --excluded-folders \"projects/essence/snapshots,scripts/openclaw\"'"

    # Install + enable systemd service
    if [ -f "$WORKSPACE/scripts/openclaw/obsidian-sync.service" ]; then
      mkdir -p ~/.config/systemd/user
      cp "$WORKSPACE/scripts/openclaw/obsidian-sync.service" ~/.config/systemd/user/
      systemctl --user daemon-reload
      systemctl --user enable obsidian-sync
      systemctl --user start obsidian-sync
      success "Obsidian Sync service started"
    fi
  else
    success "Obsidian Sync already configured"
  fi
fi


# ── 12. Install + start OpenClaw gateway service ─────────────────────────────
info "Installing OpenClaw gateway service..."
openclaw gateway install
# ── 12a. Playwright + OpenClaw browser config (Linux only) ───────────────────
if [[ "$OSTYPE" != "darwin"* ]]; then
  info "Installing Playwright globally..."
  npm install -g playwright

  info "Downloading Playwright Chromium..."
  NODE_PATH="$HOME/.npm-global/lib/node_modules" \
    "$HOME/.npm-global/bin/playwright" install chromium

  HEADLESS_SHELL=$(find "$HOME/.cache/ms-playwright" -name "headless_shell" -type f 2>/dev/null | head -1)
  if [ -n "$HEADLESS_SHELL" ]; then
    python3 -c "
import json
path = '$HOME/.openclaw/openclaw.json'
with open(path) as f: d = json.load(f)
d['browser'] = {'enabled': True, 'executablePath': '$HEADLESS_SHELL', 'headless': True, 'noSandbox': True, 'defaultProfile': 'openclaw'}
with open(path, 'w') as f: json.dump(d, f, indent=2)
" && success "OpenClaw browser configured"

    mkdir -p "$HOME/.config/systemd/user"
    cp "$HOME/.openclaw/workspace/scripts/openclaw/playwright-browser.service" \
       "$HOME/.config/systemd/user/playwright-browser.service" 2>/dev/null || true
    systemctl --user daemon-reload
    systemctl --user enable playwright-browser
    systemctl --user start playwright-browser
    success "Playwright browser server started"
  else
    warn "Could not find Playwright headless_shell — configure browser manually"
  fi
fi





# ── pixsum deployment ────────────────────────────────────────────────────────
if [[ "$OSTYPE" != "darwin"* ]]; then
  if [ ! -d "$HOME/src/pixsum/.git" ]; then
    info "Cloning pixsum..."
    mkdir -p "$HOME/src"
    git clone git@github.com:danethomas/pixsum.git "$HOME/src/pixsum"
    cd "$HOME/src/pixsum" && npm install
    success "pixsum cloned and dependencies installed"
  else
    success "pixsum already present"
  fi

  # Restore .env from 1Password
  PIXSUM_ENV="$HOME/src/pixsum/.env"
  OPENROUTER_KEY=$(op read "op://Keys/OpenRouter - Gensum/credential" 2>/dev/null || echo "")
  PIXSUM_KEY=$(op read "op://Keys/Pixsum API Key/credential" 2>/dev/null || echo "")
  if [ -n "$OPENROUTER_KEY" ] && [ -n "$PIXSUM_KEY" ]; then
    cat > "$PIXSUM_ENV" << ENVEOF
OPENROUTER_API_KEY=$OPENROUTER_KEY
PIXSUM_API_KEY=$PIXSUM_KEY
PORT=3000
CACHE_DIR=./cache
IMAGE_MODEL=google/gemini-2.5-flash-image
ENVEOF
    success "pixsum .env written from 1Password"
  else
    warn "Could not fetch pixsum keys from 1Password — write $PIXSUM_ENV manually"
  fi

  # Install systemd service
  sudo cp "$HOME/src/pixsum/pixsum.service" /etc/systemd/system/ 2>/dev/null ||   sudo tee /etc/systemd/system/pixsum.service << SVCEOF
[Unit]
Description=pixsum.dev AI image placeholder server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/src/pixsum
EnvironmentFile=$HOME/src/pixsum/.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVCEOF
  sudo systemctl daemon-reload
  sudo systemctl enable pixsum
  sudo systemctl start pixsum
  success "pixsum service started"
fi

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
