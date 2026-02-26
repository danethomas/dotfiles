# 1Password Setup

Before running `install.sh` on a new machine, ensure these items exist in your
**Private** 1Password vault. chezmoi will pull secrets from here when applying
the OpenClaw config template.

## Required Items

| 1Password Item                  | Field        | Secret                              |
|---------------------------------|--------------|-------------------------------------|
| `Gemini API`                    | `credential` | Gemini API key                      |
| `GitHub PAT (openclaw)`         | `credential` | GitHub Personal Access Token        |
| `GOG Keyring`                   | `password`   | GOG keyring password                |
| `OpenRouter API`                | `credential` | OpenRouter API key                  |
| `ElevenLabs API`                | `credential` | ElevenLabs API key                  |
| `Sparky Telegram Bot`           | `credential` | Telegram bot token                  |
| `Sparky Discord Bot`            | `credential` | Discord bot token                   |
| `Brave Search API`              | `credential` | Brave Search API key                |

## Quickstart

```bash
# 1. Sign in to 1Password CLI
op signin

# 2. Verify an item is accessible
op read "op://Private/Gemini API/credential"

# 3. Run the bootstrap
bash install.sh
```

## Adding a new secret

1. Add the item to 1Password (Private vault)
2. Add `{{ onepasswordRead "op://Private/<Item>/<field>" }}` to the relevant
   `.tmpl` file in `home/`
3. Run `chezmoi apply` to re-render templates on the current machine
4. Commit the template change (not the secret)
