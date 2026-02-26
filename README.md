# dotfiles

Personal dotfiles for Dane Thomas — managed with [chezmoi](https://chezmoi.io).
Secrets pulled from 1Password at apply time. No plaintext credentials in this repo.

## Fresh machine setup

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/danethomas/dotfiles/main/install.sh)
```

That single command:
1. Installs system packages (Node, Bun, gh, Tailscale, 1Password CLI, OpenClaw)
2. Installs chezmoi and applies all dotfiles
3. Pulls secrets from 1Password to render config templates
4. Clones the OpenClaw workspace repo to `~/.openclaw/workspace`

## Prerequisites

- Fresh Ubuntu (ARM64 or x86_64)
- 1Password CLI signed in: `op signin`
- See [docs/1password-setup.md](docs/1password-setup.md) for required vault items

## Structure

```
dotfiles/
  install.sh                              ← entry point (SSH + gh auth + Tailscale + workspace)
  packages/
    ubuntu.sh                             ← idempotent: Node, Bun, gh, Tailscale, 1Pass, Docker, OpenClaw
  home/
    dot_bashrc                            → ~/.bashrc (aliases, prompt, PATH)
    dot_gitconfig.tmpl                    → ~/.gitconfig
    dot_gitignore_global                  → ~/.gitignore_global (DS_Store, .env, etc.)
    private_dot_ssh/
      config                             → ~/.ssh/config (host aliases, key defaults)
  docs/
    1password-setup.md                    ← required 1Password vault items
```

## Migrating to a new machine

**On the old machine first:**
```bash
# Export everything to 1Password (credentials + openclaw.json)
eval $(op signin) && bash ~/.openclaw/workspace/scripts/export-credentials-to-1password.sh

# Stop the gateway
openclaw gateway stop
```

**On the new machine:**
```bash
# 1. Run the one-liner — installs everything, pauses for op signin
bash <(curl -fsSL https://raw.githubusercontent.com/danethomas/dotfiles/main/install.sh)

# 2. Sign in to 1Password, then re-run (idempotent — picks up where it left off)
op signin
bash <(curl -fsSL https://raw.githubusercontent.com/danethomas/dotfiles/main/install.sh)

# 3. Start the gateway
openclaw gateway start

# 4. Clone dev repos
git clone git@github.com:danethomas/essence-app.git ~/src/essence-app
git clone git@github.com:danethomas/essence-bot.git ~/src/essence-bot
git clone git@github.com:danethomas/essence.ai.git ~/src/essence.ai
```

That's it. Say hi 👋

---

## What's NOT in this repo

- **OpenClaw workspace** (`~/.openclaw/workspace`) — Sparky's memory, SOUL.md, projects etc.
  Lives in a separate private repo: `danethomas/openclaw-workspace`
- **Auth profiles** (`~/.openclaw/auth/`) — managed by OpenClaw directly
- **Exec approvals** (`~/.openclaw/exec-approvals.json`) — machine-specific

## Updating

```bash
# On the current machine — pull latest dotfiles + re-apply
chezmoi update --apply

# After changing a template
chezmoi apply
git -C ~/.local/share/chezmoi add -A && git -C ~/.local/share/chezmoi commit -m "..." && git -C ~/.local/share/chezmoi push
```
