# 🎭 MV Maestro

A comprehensive, modular bash profile enhancement system that transforms your terminal into a powerful development and system management environment. Features an interactive Textual TUI menu, 68+ smart commands with `--help` support, SSH/Tailscale wizards, and automatic dependency resolution.

**made with love by @drdeeks**

---

## ✨ Quick Start

```bash
# Clone or copy this directory
cd ~/MV-Maestro

# Add to your ~/.bashrc (append this line):
source ~/MV-Maestro/bash_enhanced.sh

# Reload shell
source ~/.bashrc
```

**That's it!** You now have:
- 🔥 Interactive menu (`dm` or `dmenu`)
- 💡 Help for every command (`command --help`)
- 🎨 Beautiful colored prompt with live stats
- 🐳 Docker TUI (`docker-tui`)
- 🔐 SSH wizard (`ssh-profile-setup`)
- 🌐 Tailscale helper (`ts-status`)

---

## 📁 Directory Structure

```
MV-Maestro/
├── bash_enhanced.sh          # Main entry point (source this)
├── menu_tui.py               # Textual TUI menu application
├── docker_tui.py             # Docker-specific TUI (optional)
├── modules/
│   ├── dynamic_core.sh       # Core commands (crypto, SSH, Git, etc.)
│   ├── dynamic_ext.sh        # Extended utilities
│   ├── dynamic_menu.sh       # Menu data & category definitions
│   ├── dynamic_menu_addons.sh # Additional commands (archive, dev tools)
│   ├── ssh_profile_setup.sh  # SSH host configuration wizard
│   └── tailscale_helper.sh   # Tailscale device/network manager
├── tests/
│   └── validate_menu.sh      # Automated command validation suite
└── docs/
    ├── README.md             # This file
    ├── AGENTS.md             # Development guidelines
    └── QUICKREF.md           # Quick reference card
```

---

## 🎯 Features Overview

### 1️⃣ Interactive Menu System

**Launch:** `dm`, `dmenu`, or `am` (alias manager)

The menu provides categorized access to all commands with descriptions:

| Category | Commands | Description |
|----------|----------|-------------|
| 🖥️ System & Resources | 8 | CPU, RAM, disk, network monitoring |
| 💻 Development Tools | 9 | Python, Node, Rust, Go, JSON tools |
| 🐳 Containers & Cloud | 10 | Docker, Tailscale, Cloudflare |
| 📝 Git & Version Control | 7 | Status, commits, branches, stats |
| 🔐 Security & Crypto | 6 | Encryption, secrets, SSH hardening |
| 📦 Archive & Files | 8 | Compress, extract, backup, sync |
| ⚙️ Configuration | 6 | Dotfiles, themes, keybindings |
| 📊 Monitoring | 8 | Logs, health, benchmarks |
| 🛠️ Utilities | 8 | Calculator, encoding, notes, todo |

**Menu Features:**
- **Smart search**: Type to filter commands
- **Interactive execution**: Commands run with proper TTY handoff
- **Category navigation**: Tree sidebar with keyboard shortcuts
- **Command details**: Full descriptions and usage examples

### 2️⃣ Command Line Interface

All 68+ commands support `--help` flag:

```bash
compress --help     # Compression with smart excludes
encrypt --help      # Age/GPG encryption modes
git-wip --help      # Quick WIP commit workflow
npm-check --help    # Dependency auditing
dcompose --help     # Docker Compose operations
secret-set --help   # Secure secret storage
# ... and 60+ more!
```

### 3️⃣ Wizards & Helpers

#### SSH Profile Setup Wizard
```bash
ssh-profile-setup           # Interactive VPS/host configuration
ssh-profiles                # List configured hosts
ssh-profile-remove <name>   # Remove host from inventory
ssh-batch-setup inventory.txt  # Batch import from file
```

Features:
- Guides through SSH key generation and deployment
- Creates structured config in `~/.ssh/config.d/`
- Generates convenience aliases
- Supports batch inventory imports

#### Tailscale Helper
```bash
ts-up                       # Start tailscaled + advertise routes
ts-ssh <host>              # SSH via Tailscale
ts-funnel <port>           # Expose port publicly
ts-serve <port> [path]     # Serve locally via Tailscale
ts-status                  # Pretty peer list
```

Features:
- Device management and connectivity checks
- Closed network ACL configuration wizard
- MagicDNS enablement
- Network diagnostics

### 4️⃣ Smart Auto-Resolution

Commands intelligently handle dependencies:

```bash
# compress auto-detects format and uses best available tool
compress mydir             # → mydir.tar.gz (uses tar + gzip)
compress mydir zip         # → mydir.zip (uses zip)
compress data --best       # → data.tar.xz (uses xz for max compression)

# encrypt chooses age vs GPG based on context
encrypt secret.txt         # → Symmetric (GPG/age with passphrase)
encrypt secret.txt user.age # → Asymmetric (age with recipient key)

# calc falls back gracefully
calc "2 + 2"               # Uses bc → python3 if bc unavailable
```

### 5️⃣ FZF Integration (if installed)

Keyboard shortcuts automatically bound:

| Shortcut | Function |
|----------|----------|
| `Ctrl-R` | History search |
| `Ctrl-F` | Directory jump |
| `Ctrl-G` | Git branch checkout |
| `fzf-kill` | Process picker |
| `fzf-ssh` | SSH host picker |
| `fzf-git-log` | Git log browser |

---

## 📚 Command Reference

### Archive & File Management

| Command | Description | Example |
|---------|-------------|---------|
| `compress <path> [algo]` | Compress with smart excludes | `compress project zip` |
| `extract <archive>` | Auto-detect format extraction | `extract backup.tar.gz` |
| `test-archive <file>` | Verify archive integrity | `test-archive data.zip` |
| `backup <src> [dest]` | Timestamped backup | `backup ~/data /mnt/usb` |
| `find-dupes <dir>` | Find duplicate files | `find-dupes . 5` |
| `sync-usb <dest>` | rsync to USB with excludes | `sync-usb /media/usb` |
| `sync-remote <host:path> <local>` | Remote rsync | `sync-remote user@host:/data ./local` |

### Cryptography & Secrets

| Command | Description | Example |
|---------|-------------|---------|
| `encrypt <path> [recipient]` | Age/GPG encryption | `encrypt secret.txt user@example.age` |
| `decrypt <file>` | Decrypt encrypted file | `decrypt secret.txt.age` |
| `secret-set <name> <value>` | Store encrypted secret | `secret-set api-key "abc123"` |
| `secret-get <name>` | Retrieve secret | `secret-get api-key` |
| `secret-list` | List stored secrets | `secret-list` |
| `secret-edit <name>` | Edit secret in editor | `secret-edit db-pass` |
| `ssh-hardening` | Audit SSH configuration | `ssh-hardening` |
| `cert-check <cert.pem>` | Check TLS certificate | `cert-check server.crt` |

### SSH & Tailscale

| Command | Description | Example |
|---------|-------------|---------|
| `ssh-add-key [alias]` | Interactive host setup | `ssh-add-key production` |
| `ssh-list` | List configured hosts | `ssh-list` |
| `ssh-test <alias>` | Test connection | `ssh-test staging` |
| `ssh-copy-id-auto <alias>` | Deploy SSH key | `ssh-copy-id-auto backup-server` |
| `ts-up [args]` | Start tailscaled | `ts-up --advertise-routes=10.0.0.0/24` |
| `ts-ssh <host>` | SSH via Tailscale | `ts-ssh webserver` |
| `ts-funnel <port>` | Expose port publicly | `ts-funnel 8080` |
| `ts-serve <port> [path]` | Serve locally | `ts-serve 3000 /app` |
| `ts-status` | Peer list | `ts-status` |

### Cloudflare

| Command | Description | Example |
|---------|-------------|---------|
| `cf-dns-list <zone_id>` | List DNS records | `cf-dns-list zone123` |
| `cf-dns-add <zone> <type> <name> <content>` | Add DNS record | `cf-dns-add zone123 A api example.com` |
| `cf-tunnel-create <name>` | Create cloudflared tunnel | `cf-tunnel-create prod-tunnel` |
| `cf-tunnel-route <tunnel> <host> <svc>` | Route hostname | `cf-tunnel-route prod api.example.com http://localhost:8080` |
| `cf-cache-purge <zone> [urls]` | Purge cache | `cf-cache-purge zone123` |

### Git Tools

| Command | Description | Example |
|---------|-------------|---------|
| `git-root` | CD to repo root | `git-root` |
| `git-recent [n]` | Recent branches | `git-recent 10` |
| `git-wip` | Quick WIP commit | `git-wip` |
| `git-unwip` | Undo last WIP | `git-unwip` |
| `git-standup [days]` | My commits across projects | `git-standup 30` |
| `git-prune` | Delete merged branches | `git-prune` |
| `git-largest` | Largest files in history | `git-largest` |
| `git-stats` | Repository statistics | `git-stats` |

### Docker

| Command | Description | Example |
|---------|-------------|---------|
| `docker-tui` | Full TUI (Textual) | `docker-tui` |
| `dps` | Container list | `dps` |
| `dtop` | Live stats | `dtop` |
| `dlogs <container>` | View logs | `dlogs web` |
| `dshell <container>` | Shell into container | `dshell web` |
| `dstop/dstart <container>` | Lifecycle control | `dstop web; dstart web` |
| `drm <container>` | Remove container | `drm old-container` |
| `dimages` | Image list | `dimages` |
| `dvolumes` | Volume list | `dvolumes` |
| `dnetworks` | Network list | `dnetworks` |
| `dcompose <action>` | Compose operations | `dcompose up -d` |
| `dprune` | Clean unused resources | `dprune` |

### Development Tools

| Command | Description | Example |
|---------|-------------|---------|
| `proj-scan` | Scan git repos | `proj-scan` |
| `py-fmt [dir]` | Format Python | `py-fmt /project` |
| `py-lint [dir]` | Lint Python | `py-lint .` |
| `npm-check [dir]` | Check npm deps | `npm-check ./frontend` |
| `cargo-check [dir]` | Rust check/clippy | `cargo-check ./rust-project` |
| `go-check [dir]` | Go fmt/vet/test | `go-check ./go-app` |
| `json-fmt <file>` | Format JSON | `json-fmt config.json` |
| `json-lint <file>` | Validate JSON | `json-lint data.json` |
| `json-get <file> <key>` | Extract value | `json-get config.json api.url` |
| `json-set <file> <key> <val>` | Set value | `json-set config.json version 2.0` |

### Utilities

| Command | Description | Example |
|---------|-------------|---------|
| `calc <expr>` | Calculator | `calc "sqrt(144) * 2"` |
| `cal [month] [year]` | Calendar | `cal 12 2024` |
| `encode <mode> [input]` | Encoding | `encode base64 "hello"` |
| `random <type>` | Random values | `random uuid` |
| `notes <cmd>` | Markdown notes | `notes new "Meeting"` |
| `todo <cmd>` | Task management | `todo add "Buy milk"` |
| `bench` | System benchmarks | `bench` |
| `health` | System health check | `health` |

### System Monitoring

| Command | Description | Example |
|---------|-------------|---------|
| `sysinfo` | Full system overview | `sysinfo` |
| `sysresources` | Live resources | `sysresources` |
| `diskinfo` | Disk usage | `diskinfo` |
| `myip` | Network info | `myip` |
| `psgrep <pattern>` | Find processes | `psgrep nginx` |
| `quickclean` | Clean journal/npm/pip | `quickclean` |

---

## 🔧 Customization

### Environment Variables

```bash
# Required for some features
export CF_API_TOKEN="your-cloudflare-api-token"  # Cloudflare commands
export AGE_PASSPHRASE="your-secret"                # Symmetric encryption
export EDITOR="vim"                                # Default editor (default: vim)

# Optional
export TERM=xterm-256color                         # Terminal type
```

### Adding Custom Aliases

Edit `~/.bash_aliases_usb` (created by alias manager):

```bash
# Add custom aliases
alias ll='ls -la'
alias gs='git status'
alias k='kubectl'
```

Or use the interactive alias manager:

```bash
am                          # Open alias manager menu
```

---

## 🧪 Testing & Validation

Run the validation suite to verify all commands:

```bash
./tests/validate_menu.sh    # Test all 68+ commands
```

Expected output: All commands pass with proper `--help` support.

---

## 📖 Troubleshooting

### Terminal crashes on source?

**Fixed:** Removed `set -e` from wizard files that caused interactive shell exits.

If you still experience issues:

```bash
# Temporarily disable enhanced profile
mv ~/.bashrc ~/.bashrc.backup
# Test with minimal config
echo 'PS1="\u@\h:\w\$ "' > ~/.bashrc
```

### Missing color in prompt?

Ensure `force_color_prompt=yes` is set in `.bashrc`:

```bash
echo 'force_color_prompt=yes' >> ~/.bashrc
```

### Commands not found?

Verify sourcing worked:

```bash
source ~/.bashrc
which compress              # Should show function, not binary
type dynhelp                # Should show function definition
```

### Menu not working?

Check Python/Textual availability:

```bash
python3 -c "import textual; print('OK')"  # Should print 'OK'
pip install textual                        # If missing
```

---

## 🤝 Contributing

See [`docs/AGENTS.md`](docs/AGENTS.md) for development guidelines and architecture documentation.

---

## 📄 License

This system is provided as-is for personal and professional use. Modify and distribute freely.

---

## 🙏 Credits

Built with inspiration from:
- EnhancedSystemManagement PowerShell suite
- MV Maestro design patterns
- Textual TUI framework
- fzf fuzzy finder

---

**Version:** 2.0.0  
**Last Updated:** October 2024  
**Maintained By:** @drdeeks
