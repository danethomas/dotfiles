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

## User account

Run everything as a non-root user. On AWS this is `ubuntu` by default. On Hetzner (and most VPS providers) you're dropped into root — create a user first:

```bash
adduser --disabled-password --gecos "" ubuntu
usermod -aG sudo ubuntu
su - ubuntu
```

All paths in this setup assume `~/` resolves to `/home/ubuntu`. Running as root will break them.

> **Note:** If you copy SSH keys or create `.ssh` directories using `sudo`, the home directory can end up root-owned. Fix it before running the install script:
> ```bash
> chown -R ubuntu:ubuntu /home/ubuntu
> ```

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
# 1. Stop the gateway — no more writes (heartbeats, cron jobs, etc.)
openclaw gateway stop

# 2. Backup workspace to GitHub — clean final snapshot
bash ~/.openclaw/workspace/scripts/workspace-backup.sh

# 3. Export credentials to 1Password
eval $(op signin) && bash ~/.openclaw/workspace/scripts/export-credentials-to-1password.sh

# 4. Disconnect from Tailscale
sudo tailscale down
```

**On the new machine:**
```bash
# 1. Run the one-liner — installs everything, pauses for op signin
bash <(curl -fsSL https://raw.githubusercontent.com/danethomas/dotfiles/main/install.sh)

# 2. Sign in to 1Password, then re-run (idempotent — picks up where it left off)
op signin
bash <(curl -fsSL https://raw.githubusercontent.com/danethomas/dotfiles/main/install.sh)

# 3. Copy openclaw.json from the old machine (not in any repo — manual step)
# scp ubuntu@old-machine:~/.openclaw/openclaw.json ~/.openclaw/openclaw.json

# 4. Start the gateway (install.sh runs gateway install, so this should just work)
openclaw gateway start

# 4. Clone dev repos into ~/src/
# git clone git@github.com:you/your-repo.git ~/src/your-repo
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
