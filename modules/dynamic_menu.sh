#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Unified Navigation Menu — Consistent interface for all enhanced bash features
# Source from ~/.bashrc:  source ~/.bash_profile_enhanced/modules/dynamic_menu.sh
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# DEPENDENCIES & SETUP
# ─────────────────────────────────────────────────────────────────────────────
_has() { command -v "$1" >/dev/null 2>&1; }
_die() { echo -e "\033[0;31m✗\033[0m $*" >&2; return 1; }
_ok()  { echo -e "\033[0;32m✓\033[0m $*"; }
_info() { echo -e "\033[0;34mℹ\033[0m $*"; }
_warn() { echo -e "\033[1;33m⚠\033[0m $*"; }

# Colors
: "${RED:=\033[0;31m}" "${GREEN:=\033[0;32m}" "${YELLOW:=\033[1;33m}"
: "${BLUE:=\033[0;34m}" "${CYAN:=\033[0;36m}" "${BOLD:=\033[1m}" "${DIM:=\033[2m}" "${NC:=\033[0m}"

# fzf is only required for the legacy text-menu fallback (_menu_show_main_fzf).
# The primary menu is now the Textual TUI (menu_tui.py); fzf absence is non-fatal here.
_has fzf || _warn "fzf not found — legacy text-menu fallback (dmenu-legacy) will be unavailable"

# ─────────────────────────────────────────────────────────────────────────────
# MENU DATA STRUCTURE
# ─────────────────────────────────────────────────────────────────────────────

# Each category: "icon name|description|command|submenu_items"
# command: function to call, or empty for submenu
# submenu_items: newline-separated "label|command|description"

# Category 1: System & Resources
MENU_SYS=(
    "🖥️  System Overview|Full system info (CPU, RAM, disk, tools)|sysinfo|"
    "📊 Live Resources|Real-time CPU, memory, top processes|sysresources|"
    "💾 Disk Usage|Disk breakdown + largest dirs|diskinfo|"
    "🌐 Network|IP addresses, ports, connectivity|myip|"
    "🔍 Process Manager|Find, list, kill processes|psgrep|"
    "🧹 Quick Clean|Journal, APT, npm, pip, thumbnails|quickclean|"
    "📦 Backup Projects|Timestamped backup of ~/projects|backup-projects|"
    "⚙️  Services|systemd status/enable/disable/restart|svcstatus|"
)

# Category 2: Development Tools
MENU_DEV=(
    "📁 Project Scanner|Find git repos, show status|proj-scan|"
    "🔧 Environment|Check PATH, managed dirs, auto-fix|checkenv|"
    "🐍 Python|Format (black/ruff), lint, venv|py-fmt|"
    "📦 Node.js|npm/yarn/pnpm, audit, outdated|npm-check|"
    "🦀 Rust|cargo check, build, test, fmt, clippy|cargo-check|"
    "🐹 Go|go fmt, vet, test, mod tidy|go-check|"
    "📝 JSON Tools|fmt, lint, get, set, validate|json-fmt|"
    "🔍 Find Dupes|Scan dirs for duplicate files (size/hash)|find-dupes|"
    "📋 Todo|Quick task management|todo|"
)

# Category 3: Containers & Cloud
MENU_CONTAINERS=(
    "🐳 Docker TUI|Full container management (Textual)|docker-tui|"
    "📦 Containers|List, start, stop, logs, shell, inspect|dps|"
    "🖼️  Images|List, pull, build, prune, remove|dimages|"
    "💾 Volumes|List, create, remove, prune|dvolumes|"
    "🌐 Networks|List, create, inspect, prune|dnetworks|"
    "📋 Compose|Up, down, logs, ps, build|dcompose|"
    "🧹 Prune|Remove stopped containers, dangling images, unused volumes|dprune|"
    "☁️  Cloudflare|DNS, tunnels, cache purge|cf-dns-list|"
    "🔗 Tailscale|SSH, funnel, serve, status|ts-status|"
)

# Category 4: Git & Version Control
MENU_GIT=(
    "📋 Status|Enhanced git status with colors|gs|"
    "📝 Commit|Quick commit with message|gc|"
    "🔀 Branches|Recent branches, checkout, prune|git-recent|"
    "📜 History|Graph log, standup, largest files|gl|"
    "🔍 Search|grep across repo, fuzzy log|fzf-git-log|"
    "🔧 Repo Tools|Root, wip/unwip, prune, bisect|git-root|"
    "📊 Stats|Contributors, churn, heatmap|git-stats|"
)

# Category 5: Security & Crypto
MENU_SECURITY=(
    "🔐 Encrypt|age/gpg encrypt files/dirs|encrypt|"
    "🔓 Decrypt|Decrypt .age/.gpg files|decrypt|"
    "🗝️  Secrets|Store, retrieve, edit, list (gpg)|secret-set|"
    "🔑 SSH|Add key, list, test, copy-id|ssh-add-key|"
    "🛡️  SSH Harden|Audit config, perms, keys|ssh-hardening|"
    "📜 Certificates|View, verify, generate TLS certs|cert-check|"
)

# Category 6: Archive & Files
MENU_ARCHIVE=(
    "📦 Compress|Auto-detect file/dir, smart excludes, progress|compress|"
    "📂 Extract|Multi-format with progress, .bundle support|extract|"
    "✅ Test Archive|Verify integrity without extracting|test-archive|"
    "🔍 Find Files|By name, size, date, type|findfile|"
    "📏 Largest Files|Top files by size in dir|fsize|"
    "🔄 Sync|rsync with smart excludes (USB, remote)|sync-usb|"
    "🕐 Timestamped Backup|Auto-name, retention, encryption|backup|"
)

# Category 7: Configuration & Dotfiles
MENU_CONFIG=(
    "📝 Edit Config|Open ~/.bashrc, ~/.config, etc.|edit-config|"
    "🔧 Dotfiles|Manage, sync, backup dotfiles|dotfiles|"
    "🎨 Theme|Switch color schemes, prompts|theme|"
    "⌨️  Keybindings|View, customize all bindings|keys|"
    "📦 Packages|List, update, audit installed packages|pkg-audit|"
    "🔄 Sync Config|Push/pull config to remote|sync-config|"
)

# Category 8: Monitoring & Diagnostics
MENU_MONITOR=(
    "📈 System Monitor|Live dashboard (btop/htop/glances)|sysmon|"
    "📊 Logs|journalctl, syslog, app logs with follow|logs|"
    "🔥 CPU/Mem|Per-process, historical, alerts|cpu-mem|"
    "💿 Disk I/O|iotop, iostat, smartctl|disk-io|"
    "🌐 Network|nethogs, iftop, ss, bandwhich|net-mon|"
    "🎮 GPU|nvidia-smi, rocm-smi, intel_gpu_top|gpu-mon|"
    "🧪 Benchmarks|CPU, disk, network, memory|bench|"
    "🏥 Health|SMART, temps, fans, battery|health|"
)

# Category 9: Utilities & Extras
MENU_UTILS=(
    "🧮 Calculator|bc, python, units conversion|calc|"
    "📅 Calendar|cal, reminders, time zones|cal|"
    "🔤 Encoding|base64, url, html, rot13|encode|"
    "🎲 Random|UUID, password, dice, shuffle|random|"
    "📐 Units|Convert between units|units|"
    "🌐 Web|HTTPie, curl, wget helpers|web|"
    "📝 Notes|Quick markdown notes, search|notes|"
    "⏰ Timer|Countdown, stopwatch, pomodoro|timer|"
)

# All categories for main menu
declare -A MENU_CATEGORIES=(
    ["1"]="🖥️  System & Resources|MENU_SYS"
    ["2"]="💻 Development Tools|MENU_DEV"
    ["3"]="🐳 Containers & Cloud|MENU_CONTAINERS"
    ["4"]="📝 Git & Version Control|MENU_GIT"
    ["5"]="🔐 Security & Crypto|MENU_SECURITY"
    ["6"]="📦 Archive & Files|MENU_ARCHIVE"
    ["7"]="⚙️  Configuration|MENU_CONFIG"
    ["8"]="📊 Monitoring|MENU_MONITOR"
    ["9"]="🛠️  Utilities|MENU_UTILS"
)

# ─────────────────────────────────────────────────────────────────────────────
# DATA EXPORT — single source of truth for the Textual TUI (menu_tui.py)
# Emits: CATEGORY<US>num<US>label   and  
#        ITEM<US>num<US>label<US>desc<US>cmd<US>interactive<US>purpose<US>includes<US>usage
# <US> = ASCII Unit Separator (0x1F), safe against emoji/pipe chars in labels.
# Fields 6-9 optional: interactive (y/n), purpose, comma-sep features, usage placeholder
# ─────────────────────────────────────────────────────────────────────────────
_menu_dump_data() {
    local sep=$'\x1f'
    for num in 1 2 3 4 5 6 7 8 9; do
        local cat="${MENU_CATEGORIES[$num]}"
        local label="${cat%%|*}"
        local arr_name="${cat##*|}"
        printf 'CATEGORY%s%s%s%s\n' "$sep" "$num" "$sep" "$label"

        local items_var="${arr_name}[@]"
        local items=("${!items_var}")
        for item in "${items[@]}"; do
            IFS='|' read -r ilabel idesc icmd isubmenu <<< "$item"
            # Default values - override per-item below
            local interactive="n"
            local purpose=""
            local includes=""
            local usage=""
            
            # Per-item metadata overrides (add as needed)
            case "$icmd" in
                ssh-add-key) 
                    interactive="y"; purpose="Interactive SSH key setup wizard"; includes="Key generation, config entry, connection test"
                    usage="ssh-add-key <alias> [hostname] [user]" ;;
                ssh-list) purpose="List all configured SSH hosts"; usage="ssh-list [--verbose]" ;;
                ssh-test) interactive="y"; purpose="Test SSH connection with verbose output"; usage="ssh-test <alias>" ;;
                encrypt) 
                    interactive="y"; purpose="Encrypt files using age or GPG"; includes="Recipient encryption, passphrase mode, armor/sign options"
                    usage="encrypt <file|dir> [recipient@key] [--armor] [--sign]" ;;
                decrypt) 
                    interactive="y"; purpose="Decrypt .age or .gpg files"; usage="decrypt <file.age|file.gpg> [--output dest]" ;;
                secret-set) interactive="y"; purpose="Store encrypted secrets in ~/.secrets/"; usage="secret-set <name> <value>" ;;
                secret-get) purpose="Retrieve secret by name"; usage="secret-get <name>" ;;
                secret-list) purpose="List all stored secrets"; usage="secret-list" ;;
                edit-config) 
                    interactive="y"; purpose="Interactive config file editor"; includes=".bashrc, bash_enhanced.sh, ~/.config, SSH config"
                    usage="edit-config [option]  # Interactive menu" ;;
                dotfiles) 
                    interactive="y"; purpose="Manage and sync dotfiles"; includes="Backup, sync, status check"
                    usage="dotfiles [backup|sync|status]" ;;
                theme) interactive="y"; purpose="Switch color schemes and prompt styles"; usage="theme [number]" ;;
                keys) purpose="View and customize shell keybindings"; usage="keys [--list|--bind]" ;;
                am) 
                    interactive="y"; purpose="Interactive alias manager"; includes="Create, remove, search, export aliases"
                    usage="am [--list|--add 'name=cmd'|--remove name|--search pattern|--export]" ;;
                docker-tui) 
                    interactive="y"; purpose="Full Docker resource management TUI"; includes="Containers, images, volumes, networks, compose"
                    usage="docker-tui  # Launches Python TUI application" ;;
                sysinfo) 
                    purpose="Full system overview"; includes="CPU, RAM, disk, network, uptime, tool availability"
                    usage="sysinfo  # One-shot system summary" ;;
                sysresources) 
                    interactive="y"; purpose="Live system monitoring"; includes="CPU, memory, top processes"
                    usage="sysresources  # Runs btop/htop/top interactively" ;;
                diskinfo) 
                    interactive="y"; purpose="Disk usage analysis"; includes="Large file finder, directory breakdown"
                    usage="diskinfo [directory]  # Analyze disk usage" ;;
                quickclean) 
                    interactive="y"; purpose="System cleanup wizard"; includes="Journal, APT, npm, pip cache cleanup"
                    usage="quickclean [--yes]  # Interactive cleanup wizard" ;;
                backup-projects) 
                    interactive="y"; purpose="Timestamped backup of ~/projects"; usage="backup-projects [destination]" ;;
                svcstatus) 
                    interactive="y"; purpose="systemd service management"; includes="Status, enable/disable, restart"
                    usage="svcstatus <service-name>  # Check/manage service" ;;
                proj-scan) purpose="Find git repositories and show status"; usage="proj-scan [max-depth]" ;;
                todo) 
                    interactive="y"; purpose="Quick task management"; includes="Add, list, mark done, clear"
                    usage="todo [add|list|done|clear] [args]" ;;
                calc) 
                    purpose="Arithmetic calculator"; includes="bc or python3 backend"
                    usage="calc '<expression>'  # e.g., calc '2 + 2 * 2'" ;;
                random) 
                    purpose="Random value generator"; includes="UUID, password, dice rolls, shuffle"
                    usage="random [uuid|pass|dice|shuffle] [args]" ;;
                encode) 
                    purpose="Encoding utilities"; includes="base64, URL, ROT13, decode"
                    usage="encode [base64|url|rot13|decode] [input]" ;;
                timer) 
                    interactive="y"; purpose="Countdown and stopwatch timers"; includes="Pomodoro mode"
                    usage="timer [countdown|pomodoro] [seconds]" ;;
                notes) 
                    interactive="y"; purpose="Markdown notes management"; includes="Create, list, search, open"
                    usage="notes [new|list|search|open] [title]" ;;
                bench) 
                    interactive="y"; purpose="System benchmarks"; includes="CPU (sysbench), disk write test"
                    usage="bench  # Runs CPU and disk benchmarks" ;;
                health) 
                    purpose="System health diagnostics"; includes="SMART status, temperatures, battery"
                    usage="health  # Hardware health check" ;;
                units) 
                    purpose="Unit conversion"; includes="Length, weight, temperature, etc."
                    usage="units '<from>' '<to>'  # e.g., units '100 miles' 'km'" ;;
                web) 
                    purpose="HTTP client helpers"; includes="GET, POST, PUT, DELETE via curl/httpie"
                    usage="web [GET|POST|PUT|DELETE] <url> [data]" ;;
                cal) 
                    purpose="Calendar viewer"; includes="Monthly calendar, reminders"
                    usage="cal [month] [year]  # Display calendar" ;;
                compress) 
                    interactive="y"; purpose="Compress files/directories"; includes="gzip, bzip2, xz, zip formats, smart excludes"
                    usage="compress <path> [algo|gzip] [output] [--no-excludes]" ;;
                extract) 
                    interactive="y"; purpose="Extract archives"; includes="tar.gz, tar.bz2, tar.xz, zip, .bundle"
                    usage="extract <archive> [dest] [--strip N]" ;;
                test-archive) 
                    purpose="Verify archive integrity"; usage="test-archive <file.tar.gz|file.zip>" ;;
                backup) 
                    interactive="y"; purpose="Timestamped file/directory backup"; usage="backup <source> [destination]" ;;
                find-dupes) 
                    purpose="Find duplicate files by size/hash"; usage="find-dupes [directory] [max-depth]" ;;
                sync-usb) 
                    interactive="y"; purpose="Sync to USB drive with smart excludes"; usage="sync-usb <destination>" ;;
                sync-config) 
                    interactive="y"; purpose="Push/pull config to remote git repo"; usage="sync-config <remote-url>" ;;
                pkg-audit) 
                    interactive="y"; purpose="Audit installed packages"; includes="APT, npm, pip outdated checks"
                    usage="pkg-audit  # Check all package managers" ;;
                cpu-mem) 
                    interactive="y"; purpose="Per-process CPU/memory monitoring"; usage="cpu-mem  # Live monitoring" ;;
                disk-io) 
                    interactive="y"; purpose="Disk I/O monitoring"; includes="iotop, iostat"
                    usage="disk-io  # Live disk I/O monitoring" ;;
                net-mon) 
                    interactive="y"; purpose="Network monitoring"; includes="nethogs, iftop, ss"
                    usage="net-mon  # Live network monitoring" ;;
                gpu-mon) 
                    interactive="y"; purpose="GPU monitoring"; includes="nvidia-smi, rocm-smi, intel_gpu_top"
                    usage="gpu-mon  # Live GPU monitoring" ;;
                logs) 
                    interactive="y"; purpose="Follow system/application logs"; includes="journalctl, syslog"
                    usage="logs  # Follow journalctl in real-time" ;;
                dlogs) 
                    interactive="y"; purpose="Docker container logs"; includes="Follow mode, tail options"
                    usage="dlogs <container> [lines]  # View container logs" ;;
                dshell) 
                    interactive="y"; purpose="Shell into Docker container"; usage="dshell <container>" ;;
                dcompose) 
                    interactive="y"; purpose="Docker Compose operations"; includes="up, down, logs, ps, build"
                    usage="dcompose [up|down|logs|ps|build] [options]" ;;
                dprune) 
                    interactive="y"; purpose="Prune Docker resources"; includes="containers, images, volumes"
                    usage="dprune  # Remove unused Docker resources" ;;
                keystore-create) 
                    interactive="y"; purpose="EVM keystore management"; includes="Create, import, export, sign, verify"
                    usage="keystore-create <name>" ;;
                keystore-sign) interactive="y"; usage="keystore-sign <name> <message>" ;;
                json-fmt) purpose="JSON manipulation tools"; usage="json-fmt <file.json>" ;;
                json-lint) purpose="Lint JSON files"; usage="json-lint <file.json>" ;;
                json-get) purpose="Get value from JSON"; usage="json-get <file.json> <key>" ;;
                json-set) purpose="Set value in JSON"; usage="json-set <file.json> <key> <value>" ;;
                py-fmt) 
                    interactive="y"; purpose="Python code formatting"; includes="black, ruff"
                    usage="py-fmt [directory]" ;;
                py-lint) 
                    interactive="y"; purpose="Python linting"; includes="ruff, flake8"
                    usage="py-lint [directory]" ;;
                cargo-check) 
                    interactive="y"; purpose="Rust project checks"; includes="check, clippy, build, test"
                    usage="cargo-check [project-dir]" ;;
                go-check) 
                    interactive="y"; purpose="Go project checks"; includes="fmt, vet, test"
                    usage="go-check [project-dir]" ;;
                npm-check) 
                    interactive="y"; purpose="Node.js dependency checks"; includes="npm/yarn/pnpm outdated, audit"
                    usage="npm-check [project-dir]" ;;
                git-stats) 
                    purpose="Git repository statistics"; includes="Contributors, activity, largest files"
                    usage="git-stats [repository]" ;;
                ssh-hardening) 
                    purpose="SSH security audit"; includes="Config review, permission checks"
                    usage="ssh-hardening  # Audit SSH configuration" ;;
                cert-check) 
                    purpose="TLS certificate inspection"; usage="cert-check <hostname>[:port]" ;;
                psgrep) 
                    purpose="Find and manage processes"; usage="psgrep <pattern>  # Fuzzy process search" ;;
                fzf-git-log) 
                    interactive="y"; purpose="Fuzzy search git log"; usage="fzf-git-log  # Interactive git log browser" ;;
                git-recent) 
                    purpose="Recent branches and checkout"; usage="git-recent  # List and switch branches" ;;
                git-root) 
                    purpose="Git repo utilities"; includes="Root dir, wip/unwip, prune"
                    usage="git-root  # Repo management tools" ;;
                gs) purpose="Git status"; usage="gs  # Enhanced git status" ;;
                gc) purpose="Git commit"; usage="gc <message>  # Quick commit" ;;
                gl) purpose="Git log graph"; usage="gl  # Visual git history" ;;
                findfile) purpose="Find files by name/size/date"; usage="findfile <pattern> [directory]" ;;
                fsize) purpose="Find largest files"; usage="fsize [directory] [count]" ;;
                checkenv) purpose="Check development environment"; usage="checkenv  # Environment validation" ;;
                cpufreq) purpose="CPU frequency scaling"; usage="cpufreq  # Show/set CPU frequency" ;;
                meminfo) purpose="Memory information"; usage="meminfo  # Detailed memory stats" ;;
                netstat) purpose="Network connections"; usage="netstat  # Active connections" ;;
                whois*) purpose="Network information lookup"; usage="whois-ip <IP> | whois-domain <domain>" ;;
                cf-*) purpose="Cloudflare DNS management"; usage="cf-dns-list | cf-dns-add <name> <type> <value>" ;;
                ts-*) purpose="Tailscale device/network management"; usage="ts-status | ts-devices | ts-closed-network" ;;
            esac
            
            # Output single line with all fields
            local line="ITEM${sep}${num}${sep}${ilabel}${sep}${idesc}${sep}${icmd}${sep}${interactive}${sep}${purpose}${sep}${includes}${sep}${usage}"
            echo "$line"
        done
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# RENDERING
# ─────────────────────────────────────────────────────────────────────────────

_menu_render_header() {
    clear
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}         Enhanced Bash — Unified Navigation Menu                    ${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${DIM}Host: $(hostname)  •  User: $USER  •  $(date '+%a %b %d %H:%M')${NC}"
    echo ""
}

_menu_render_footer() {
    echo ""
    echo -e "  ${DIM}Navigation: ↑/↓ select  •  Enter execute  •  Esc back  •  / search  •  ? help${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# CORE MENU LOGIC
# ─────────────────────────────────────────────────────────────────────────────

_menu_show_main() {
    while true; do
        _menu_render_header
        
        # Build category list for fzf
        local choices=""
        for num in 1 2 3 4 5 6 7 8 9; do
            local cat="${MENU_CATEGORIES[$num]}"
            local label="${cat%%|*}"
            choices+="$num. $label\n"
        done
        choices+="0. Exit\n"
        choices+="?. Help"
        
        # Build fzf command conditionally based on TTY
        local choice
        if [[ -t 0 ]]; then
            choice=$(echo -e "$choices" | fzf \
                --height 95% \
                --reverse \
                --header "Main Menu — Select Category" \
                --prompt "menu> " \
                --preview '
                    num=$(echo {} | cut -d. -f1)
                    case $num in
                        1) echo "System info, resources, disk, network, processes, cleanup, backup"
                        2) echo "Project scanning, env management, Python/Node/Rust/Go, JSON, dupes"
                        3) echo "Docker TUI, containers, images, volumes, networks, compose, Cloudflare"
                        4) echo "Git status, commit, branches, history, search, repo tools"
                        5) echo "Encrypt/decrypt, secrets, SSH, hardening, certificates"
                        6) echo "Compress/extract, find files, sync, timestamped backup"
                        7) echo "Edit config, dotfiles, themes, keybindings, packages"
                        8) echo "Live monitoring, logs, CPU/mem/disk/net/GPU, benchmarks"
                        9) echo "Calculator, calendar, encoding, random, units, web, notes"
                        *) echo "Enhanced Bash Navigation Menu — Consistent interface for all features"
                    esac
                ' \
                --preview-window "up:3:wrap" \
                --bind "?:toggle-preview" \
                --bind "ctrl-h:toggle-preview")
        else
            choice=$(echo -e "$choices" | fzf \
                --height 95% \
                --reverse \
                --header "Main Menu — Select Category" \
                --prompt "menu> ")
        fi
        
        [[ -z $choice ]] && break
        local num=$(echo "$choice" | cut -d. -f1)
        [[ $num == "0" ]] && break
        [[ $num == "?" ]] && _menu_show_help && continue
        [[ $num =~ ^[1-9]$ ]] && _menu_show_category "$num"
    done
}

_menu_show_category() {
    local cat_num=$1
    local cat="${MENU_CATEGORIES[$cat_num]}"
    local cat_name="${cat%%|*}"
    local arr_name="${cat##*|}"
    
    while true; do
        _menu_render_header
        echo -e "  ${BOLD}${CYAN}$cat_name${NC}"
        echo -e "  ${DIM}────────────────────────────────────────────────────${NC}"
        echo ""
        
        # Use indirect array expansion instead of nameref (more reliable)
        local items_var="${arr_name}[@]"
        local items=("${!items_var}")
        
        # Check if array is empty
        if [[ ${#items[@]} -eq 0 ]]; then
            echo -e "  ${YELLOW}No items in this category${NC}"
            echo ""
            read -rp "Press Enter to go back..." _
            break
        fi
        
        # Build item list
        local choices=""
        local idx=0
        for item in "${items[@]}"; do
            IFS='|' read -r label desc cmd submenu <<< "$item"
            idx=$((idx + 1))
            choices+="$idx. $label\n"
        done
        choices+="b. Back to Main Menu\n"
        choices+="m. Main Menu\n"
        choices+="?. Help"
        
        local choice=$(echo -e "$choices" | fzf \
            --height 95% \
            --reverse \
            --header "$cat_name — Select Action" \
            --prompt "$cat_name> " \
            --preview '
                idx=$(echo {} | cut -d. -f1)
                if [[ $idx =~ ^[0-9]+$ ]]; then
                    idx=$((idx - 1))
                    echo "Executing the selected action..."
                    echo "Press Enter to run, or Esc to cancel"
                fi
            ' \
            --preview-window "up:4:wrap" \
            --bind "?:toggle-preview" \
            --bind "ctrl-h:toggle-preview")
        
        [[ -z $choice ]] && break
        local sel=$(echo "$choice" | cut -d. -f1)
        [[ $sel == "b" ]] && break
        [[ $sel == "m" ]] && return 2
        [[ $sel == "?" ]] && _menu_show_help && continue
        
        if [[ $sel =~ ^[0-9]+$ ]]; then
            sel=$((sel - 1))
            if [[ $sel -ge 0 && $sel -lt ${#items[@]} ]]; then
                # Use indirect expansion to get the item
                local item_var="${arr_name}[$sel]"
                local item="${!item_var}"
                IFS='|' read -r label desc cmd submenu <<< "$item"
                _menu_execute_item "$label" "$cmd" "$submenu"
            fi
        fi
    done
    return 0
}

_menu_execute_item() {
    local label=$1 cmd=$2 submenu=$3
    
    # If there's a submenu, show it
    if [[ -n $submenu ]]; then
        _menu_show_submenu "$label" "$submenu"
        return
    fi
    
    # Otherwise execute the command
    if [[ -n $cmd ]]; then
        clear
        echo -e "${BOLD}${CYAN}Executing: $label${NC}"
        echo -e "${DIM}Command: $cmd${NC}"
        echo ""
        
        # Check if function exists
        if declare -f "$cmd" >/dev/null 2>&1; then
            $cmd
        elif _has "$cmd"; then
            $cmd
        else
            _warn "Command not found: $cmd"
            _info "Available as function: $(declare -f "$cmd" >/dev/null && echo yes || echo no)"
        fi
        
        echo ""
        read -rp "Press Enter to continue..."
    fi
}

_menu_show_submenu() {
    local parent_label=$1 submenu=$2
    
    while true; do
        _menu_render_header
        echo -e "  ${BOLD}${CYAN}$parent_label → Submenu${NC}"
        echo -e "  ${DIM}────────────────────────────────────────────────────${NC}"
        echo ""
        
        IFS=$'\n' read -rd '' -a sub_items <<<"$submenu"
        local choices=""
        local idx=0
        for item in "${sub_items[@]}"; do
            IFS='|' read -r label desc cmd <<< "$item"
            idx=$((idx + 1))
            choices+="$idx. $label\n"
        done
        choices+="b. Back\n"
        choices+="m. Main Menu"
        
        local choice=$(echo -e "$choices" | fzf \
            --height 90% \
            --reverse \
            --header "$parent_label — Submenu" \
            --prompt "submenu> " \
            --preview 'echo "Execute sub-action"')
        
        [[ -z $choice ]] && break
        local sel=$(echo "$choice" | cut -d. -f1)
        [[ $sel == "b" ]] && break
        [[ $sel == "m" ]] && return 2
        
        if [[ $sel =~ ^[0-9]+$ ]]; then
            sel=$((sel - 1))
            if [[ $sel -ge 0 && $sel -lt ${#sub_items[@]} ]]; then
                IFS='|' read -r label desc cmd <<< "${sub_items[$sel]}"
                clear
                echo -e "${BOLD}${CYAN}Executing: $label${NC}"
                echo ""
                if declare -f "$cmd" >/dev/null 2>&1; then
                    $cmd
                elif _has "$cmd"; then
                    $cmd
                else
                    _warn "Command not found: $cmd"
                fi
                echo ""
                read -rp "Press Enter to continue..."
            fi
        fi
    done
}

_menu_show_help() {
    clear
    cat <<'HELPEOF' | less -R

═══════════════════════════════════════════════════════════════════════
                    ENHANCED BASH — NAVIGATION HELP
═══════════════════════════════════════════════════════════════════════

MAIN MENU NAVIGATION:
  ↑/↓ / j/k     Navigate categories
  Enter         Select category
  1-9           Quick select by number
  /             Search/filter
  ?             This help
  Esc / q       Exit menu
  Ctrl-H        Toggle preview

CATEGORY MENU:
  ↑/↓ / j/k     Navigate actions
  Enter         Execute action
  1-9           Quick select by number
  b             Back to main menu
  m             Jump to main menu
  ?             This help
  /             Search/filter

ACTION EXECUTION:
  • Functions are called directly if defined
  • External commands run if in PATH
  • Output displayed, press Enter to continue
  • Errors shown but don't exit menu

KEYBOARD SHORTCUTS (Global):
  Ctrl-R        Fuzzy history search (fzf)
  Ctrl-F        Fuzzy directory jump (fzf)
  Ctrl-G        Git branch checkout (fzf)
  Tab           Next tab (in supported tools)
  Shift+Tab     Previous tab

SEARCH TIPS:
  • Type to filter in any menu
  • Use ! to exclude (e.g., "!docker")
  • Use ^ to match start (e.g., "^sys")
  • Use $ to match end (e.g., "clean$")

CUSTOMIZATION:
  • Add functions to ~/.bash_profile_enhanced/custom.sh
  • Modify MENU_* arrays in this file
  • Set DYNAMIC_MENU_FAVORITES for quick access

ENVIRONMENT VARIABLES:
  DYNAMIC_MENU_THEME     Color theme (default, dark, light)
  DYNAMIC_MENU_PREVIEW   Enable previews (1/0)
  DYNAMIC_MENU_HEIGHT    fzf height percentage (default 95%)

═══════════════════════════════════════════════════════════════════════
HELPEOF
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE PATH RESOLUTION (at load time)
# ─────────────────────────────────────────────────────────────────────────────
_DYNAMIC_MENU_DIR="${BASH_SOURCE[0]%/*}"
_DYNAMIC_CORE="${_DYNAMIC_MENU_DIR}/dynamic_core.sh"
_DYNAMIC_EXT="${_DYNAMIC_MENU_DIR}/dynamic_ext.sh"
_DOCKER_TUI="${_DYNAMIC_MENU_DIR}/../docker_tui.py"

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

# Standalone helpers (no subshell wrapping - commands are already sourced)
docker-tui() { python3 "${_DOCKER_TUI}"; }
gs() { git status; }
gc() { git commit -m "$*"; }
gl() { git log --oneline --graph --decorate --all | head -30; }
sysmon() { _has btop && btop || _has htop && htop || top; }
logs() { journalctl -f; }
cpu-mem() { watch -n1 "free -h && echo && mpstat 1 1"; }
disk-io() { _has iotop && sudo iotop || iostat -xz 1; }
net-mon() { _has nethogs && sudo nethogs || _has bandwhich && bandwhich || ss -tulpn; }
gpu-mon() { _has nvidia-smi && watch -n1 nvidia-smi || _has rocm-smi && rocm-smi || _has intel_gpu_top && intel_gpu_top; }
calc() { bc -l <<< "$*" 2>/dev/null || python3 -c "print($*)" 2>/dev/null || echo "Need bc or python3"; }

_MENU_TUI_PY="${_DYNAMIC_MENU_DIR}/../menu_tui.py"

# Detect once whether the Textual TUI is usable; cached to avoid re-checking
# `python3 -c "import textual"` on every single menu invocation.
_menu_tui_available() {
    [[ -n ${_MENU_TUI_AVAILABLE:-} ]] && { [[ $_MENU_TUI_AVAILABLE == 1 ]]; return; }
    if _has python3 && [[ -f $_MENU_TUI_PY ]] && python3 -c "import textual" >/dev/null 2>&1; then
        _MENU_TUI_AVAILABLE=1
    else
        _MENU_TUI_AVAILABLE=0
    fi
    [[ $_MENU_TUI_AVAILABLE == 1 ]]
}

# Launch the Textual TUI, optionally pre-expanded to category $1 (1-9).
# Falls back to the legacy fzf text menu if Textual/python3 is unavailable.
_menu_tui_launch() {
    local cat="${1:-}"
    if _menu_tui_available; then
        python3 "$_MENU_TUI_PY" "$cat"
    else
        _warn "Textual TUI unavailable (need python3 + 'pip install textual') — using legacy fzf menu"
        if [[ -n $cat ]]; then
            _menu_show_category "$cat"
        else
            _menu_show_main
        fi
    fi
}

# Main menu function — Textual TUI (primary), fzf text menu (fallback)
dmenu() {
    _menu_tui_launch
}

# Legacy fzf-based menu, always available on demand regardless of Textual
dmenu-legacy() {
    _menu_show_main
}

# Quick category access by number
dmenu-sys() { _menu_tui_launch 1; }
dmenu-dev() { _menu_tui_launch 2; }
dmenu-containers() { _menu_tui_launch 3; }
dmenu-git() { _menu_tui_launch 4; }
dmenu-security() { _menu_tui_launch 5; }
dmenu-archive() { _menu_tui_launch 6; }
dmenu-config() { _menu_tui_launch 7; }
dmenu-monitor() { _menu_tui_launch 8; }
dmenu-utils() { _menu_tui_launch 9; }

_menu_show_category_by_num() {
    local num=$1
    local cat="${MENU_CATEGORIES[$num]}"
    local label="${cat%%|*}"
    local array="${cat##*|}"
    _menu_show_category "$num"
}

# Aliases for quick access
alias dm='dmenu'
alias dms='dmenu-sys'
alias dmd='dmenu-dev'
alias dmc='dmenu-containers'
alias dmg='dmenu-git'
alias dmsec='dmenu-security'
alias dma='dmenu-archive'
alias dmc2='dmenu-config'
alias dmm='dmenu-monitor'
alias dmu='dmenu-utils'

# ─────────────────────────────────────────────────────────────────────────────
# COMPLETION (for menu commands)
# ─────────────────────────────────────────────────────────────────────────────

_dmenu_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local commands="dmenu dm dms dmd dmc dmg dmsec dma dmc2 dmm dmu"
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
}
complete -F _dmenu_completions dmenu dm dms dmd dmc dmg dmsec dma dmc2 dmm dmu

# ─────────────────────────────────────────────────────────────────────────────
# INIT MESSAGE (single consolidated message for all dynamic modules)
# ─────────────────────────────────────────────────────────────────────────────
[[ $- == *i* ]] && _info "Dynamic modules loaded. Type ${CYAN}mvhelp${NC} or ${CYAN}dynhelp${NC} for help, ${CYAN}dm${NC} for menu."