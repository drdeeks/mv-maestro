# 🚀 Quick Reference Card

## Installation

```bash
./install.sh ~/MV-Maestro  # Install
source ~/.bashrc                      # Activate
```

---

## Essential Commands

| Command | Description |
|---------|-------------|
| `dm` or `dmenu` | Interactive menu (all commands) |
| `dynhelp` | Full command reference |
| `mvhelp` | System overview help |
| `am` | Alias manager |

---

## Most Used Commands

### Files & Archive
```bash
compress mydir              # Compress directory
extract backup.tar.gz       # Extract archive
backup ~/data /mnt/usb      # Timestamped backup
find-dupes .                # Find duplicates
```

### Security
```bash
encrypt secret.txt          # Encrypt file
decrypt secret.txt.age      # Decrypt file
secret-set api-key "abc"    # Store secret
secret-get api-key          # Retrieve secret
```

### Git
```bash
git-root                    # CD to repo root
git-wip                     # Quick commit
git-unwip                   # Undo WIP
git-prune                   # Clean merged branches
```

### Docker
```bash
docker-tui                  # Full TUI
dps                         # Container list
dlogs web                   # View logs
dcompose up                 # Start services
```

### Dev Tools
```bash
py-fmt                      # Format Python
npm-check                   # Check dependencies
json-fmt config.json        # Format JSON
cargo-check                 # Rust check
```

### Utilities
```bash
calc "2 + 2 * 2"            # Calculator
encode base64 "hello"       # Base64 encode
random uuid                 # Generate UUID
todo add "Buy milk"         # Add task
notes new "Meeting"         # Create note
```

### SSH & Network
```bash
ssh-profile-setup           # Configure host
ts-status                   # Tailscale status
ts-ssh server               # SSH via Tailscale
myip                        # Show IP info
```

---

## FZF Shortcuts (if installed)

| Keys | Action |
|------|--------|
| `Ctrl-R` | History search |
| `Ctrl-F` | Directory jump |
| `Ctrl-G` | Git branch checkout |

---

## Environment Variables

```bash
export CF_API_TOKEN="..."   # Cloudflare API
export AGE_PASSPHRASE="..." # Encryption passphrase
export EDITOR="vim"         # Default editor
```

---

## Troubleshooting

```bash
# Reload configuration
source ~/.bashrc

# Test installation
which compress
dynhelp | head -10

# Run validation
~/MV-Maestro/tests/validate_menu.sh
```

---

**More Info:** See `README.md` for full documentation  
**Development:** See `docs/AGENTS.md` for architecture
