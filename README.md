# MV Maestro

[![DrDeeks Project](https://img.shields.io/badge/DrDeeks%20Project-171718?style=flat-square&labelColor=b84d32)](https://github.com/drdeeks)

A modular Bash profile enhancement system that turns a Linux terminal into a practical development and system-management console, with 68+ documented commands, an interactive Textual menu, SSH/Tailscale helpers, and dependency-aware fallbacks.

## Quick start

```bash
./install.sh ~/MV-Maestro
source ~/MV-Maestro/bash_enhanced.sh
```

Or source the project directly:

```source ./bash_enhanced.sh```

## Included tools

- Interactive menu: `dm`, `dmenu`
- System, Git, Docker, archive, crypto, and developer utilities
- SSH profile setup and batch inventory helpers
- Tailscale status, SSH, serve, and funnel helpers
- Optional Textual and Docker TUIs
- Automated command/help validation in `tests/validate_menu.sh`

## Layout

- `bash_enhanced.sh` — entry point
- `modules/` — command and menu modules
- `menu_tui.py` — interactive Textual menu
- `tests/` — validation suite
- `docs/` — architecture, quick reference, and contributor guidance

Run any command with `--help` for usage. Read [docs/README.md](docs/README.md) for the full command reference and [docs/AGENTS.md](docs/AGENTS.md) before changing modules.
