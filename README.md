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
  install.sh                              ← entry point
  packages/
    ubuntu.sh                             ← idempotent package installs
  home/
    dot_gitconfig.tmpl                    → ~/.gitconfig
    private_dot_openclaw/
      private_openclaw.json.tmpl          → ~/.openclaw/openclaw.json (secrets via 1Password)
  docs/
    1password-setup.md                    ← required 1Password items
```

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
