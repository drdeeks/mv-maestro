# MV Maestro

[![Bash](https://img.shields.io/badge/Bash-modular%20CLI-4EAA25?logo=gnubash&logoColor=white)](bash_enhanced.sh) [![Python](https://img.shields.io/badge/Python-TUI-3776AB?logo=python&logoColor=white)](menu_tui.py) [![Textual](https://img.shields.io/badge/Textual-optional%20UI-5C2D91)](textual-tui-skill/)

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
