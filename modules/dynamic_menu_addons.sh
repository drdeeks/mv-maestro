#!/usr/bin/env bash
# =============================================================================
# Additional Menu Command Implementations
# These fill in the gaps for menu items that were previously unimplemented
# Source from: ~/.bash_profile_enhanced/modules/dynamic_ext.sh (appended)
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# DEVELOPMENT TOOLS
# ─────────────────────────────────────────────────────────────────────────────

# proj-scan - Find git repos and show status
proj-scan() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: proj-scan              Scan for git repositories

Finds all git repos in ~/projects and shows their status.

Output:
  Repository name, path, and uncommitted changes

Examples:
  proj-scan                   # Scan all projects
HELP
        return 0
    }
    echo "Scanning for git repositories..."
    find ~ -maxdepth 4 -type d -name ".git" 2>/dev/null | while read -r gitdir; do
        local repo_dir=$(dirname "$gitdir")
        local repo_name=$(basename "$repo_dir")
        echo ""
        echo "=== $repo_name ($repo_dir) ==="
        cd "$repo_dir" && git status --short 2>/dev/null || true
    done
}

# npm-check - npm/yarn/pnpm audit and outdated
npm-check() {
    local dir="${1:-.}"
    [[ "$dir" == "--help" || "$dir" == "-h" ]] && {
        cat <<'HELP'
Usage: npm-check [directory]

Check npm/yarn/pnpm dependencies for outdated packages and vulnerabilities.

Arguments:
  directory       Project directory (default: current)

Checks:
  • Outdated packages
  • Security audits (npm audit)
  • Vulnerability reports

Examples:
  npm-check                   # Check current dir
  npm-check /path/to/project  # Check specific project
HELP
        return 0
    }
    cd "$dir" || return 1
    
    if [[ -f package.json ]]; then
        echo "Checking npm dependencies..."
        if _has npm; then
            npm outdated 2>/dev/null || echo "No outdated packages"
            echo ""
            npm audit --audit-level=moderate 2>/dev/null || true
        fi
        if _has yarn; then
            echo ""
            yarn outdated 2>/dev/null || echo "No yarn outdated packages"
        fi
        if _has pnpm; then
            echo ""
            pnpm outdated 2>/dev/null || echo "No pnpm outdated packages"
        fi
    else
        echo "No package.json found in $dir"
    fi
}

# cargo-check - cargo check, build, test, fmt, clippy
cargo-check() {
    local dir="${1:-.}"
    [[ "$dir" == "--help" || "$dir" == "-h" ]] && {
        cat <<'HELP'
Usage: cargo-check [directory]

Run Rust cargo checks (check, clippy).

Arguments:
  directory       Rust project directory (default: current)

Checks:
  • cargo check   Syntax and type checking
  • cargo clippy  Linting with best practices

Examples:
  cargo-check                 # Check current project
  cargo-check /path/to/rust   # Check specific project
HELP
        return 0
    }
    cd "$dir" || return 1
    
    if [[ -f Cargo.toml ]]; then
        echo "Running cargo check..."
        cargo check 2>&1 | tail -20
        echo ""
        echo "Running cargo clippy..."
        cargo clippy -- -D warnings 2>&1 | tail -20
    else
        echo "No Cargo.toml found in $dir"
    fi
}

# go-check - go fmt, vet, test, mod tidy
go-check() {
    local dir="${1:-.}"
    [[ "$dir" == "--help" || "$dir" == "-h" ]] && {
        cat <<'HELP'
Usage: go-check [directory]

Run Go checks (fmt, vet, test, mod tidy).

Arguments:
  directory       Go project directory (default: current)

Checks:
  • go fmt      Format code
  • go vet      Static analysis
  • go test     Run tests
  • go mod tidy  Clean dependencies

Examples:
  go-check                  # Check current project
  go-check /path/to/go      # Check specific project
HELP
        return 0
    }
    cd "$dir" || return 1
    
    if [[ -f go.mod ]]; then
        echo "Running go fmt..."
        go fmt ./...
        echo ""
        echo "Running go vet..."
        go vet ./...
        echo ""
        echo "Running go test..."
        go test ./... -v 2>&1 | tail -30
    else
        echo "No go.mod found in $dir"
    fi
}

# todo - Quick task management
todo() {
    local todo_file="$HOME/.todo"
    mkdir -p "$(dirname "$todo_file")"
    
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: todo <command> [args]

Quick task management in ~/.todo file.

Commands:
  add <task>      Add new task
  list            Show all tasks (default)
  done <num>      Mark task as complete
  clear           Remove all tasks

Examples:
  todo add "Buy milk"         # Add task
  todo                        # List tasks
  todo done 1                 # Complete task #1
  todo clear                  # Clear all tasks
HELP
        return 0
    }
    
    case "${1:-list}" in
        add|a)
            shift
            [[ -z "$1" ]] && { echo "Usage: todo add <task>"; return 1; }
            echo "$(date '+%Y-%m-%d %H:%M') [ ] $*" >> "$todo_file"
            echo "✓ Added task"
            ;;
        list|l|"")
            echo "=== TODO ==="
            if [[ -f "$todo_file" ]]; then
                cat "$todo_file" | nl
            else
                echo "(no tasks)"
            fi
            ;;
        done|d)
            shift
            [[ -z "$1" ]] && { echo "Usage: todo done <line_number>"; return 1; }
            sed -i "${1}s/\[ \]/[x]/" "$todo_file"
            echo "✓ Marked task #$1 as done"
            ;;
        clear|c)
            > "$todo_file"
            echo "✓ Cleared all tasks"
            ;;
        *)
            echo "Usage: todo [add|list|done|clear]"
            echo "  todo add <task>     - Add a new task"
            echo "  todo list           - List all tasks"
            echo "  todo done <number>  - Mark task as done"
            echo "  todo clear          - Clear all tasks"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# GIT & VERSION CONTROL
# ─────────────────────────────────────────────────────────────────────────────

# git-stats - Contributors, churn, heatmap
git-stats() {
    local dir="${1:-.}"
    cd "$dir" || return 1
    
    if ! _is_git_repo; then
        echo "Not a git repository"
        return 1
    fi
    
    echo "=== Git Repository Statistics ==="
    echo ""
    echo "Contributors:"
    git shortlog -sn | head -10
    echo ""
    echo "Recent activity (last 30 days):"
    git log --since="30 days ago" --oneline | wc -l
    echo " commits"
    echo ""
    echo "Largest files:"
    git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | awk '/^blob/ {print $3, $4}' | sort -rn | head -5 | numfmt --field=1 --to=iec
}

_is_git_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# ssh-hardening - Audit SSH config, permissions, keys
ssh-hardening() {
    echo "=== SSH Security Audit ==="
    echo ""
    
    # Check sshd_config if root
    if [[ $EUID -eq 0 ]] && [[ -f /etc/ssh/sshd_config ]]; then
        echo "sshd_config settings:"
        grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|X11Forwarding)" /etc/ssh/sshd_config 2>/dev/null || echo "(not set or commented)"
        echo ""
    fi
    
    # Check user SSH config
    if [[ -f ~/.ssh/config ]]; then
        echo "~/.ssh/config exists"
        echo "Permissions: $(stat -c '%a' ~/.ssh/config 2>/dev/null || stat -f '%Sp' ~/.ssh/config)"
        echo ""
    fi
    
    # Check key permissions
    echo "Key file permissions:"
    for key in ~/.ssh/id_*; do
        [[ -f "$key" && ! "$key" =~ \.pub$ ]] && {
            perms=$(stat -c '%a' "$key" 2>/dev/null || stat -f '%Sp' "$key")
            if [[ "$perms" != "600" && "$perms" != "-rw-------" ]]; then
                echo "⚠ $key has insecure permissions: $perms (should be 600)"
            else
                echo "✓ $(basename "$key")"
            fi
        }
    done
    echo ""
    
    # Known hosts
    if [[ -f ~/.ssh/known_hosts ]]; then
        echo "Known hosts entries: $(wc -l < ~/.ssh/known_hosts)"
    fi
}

# cert-check - View, verify, generate TLS certs
cert-check() {
    local host="${1:-}"
    
    if [[ -n "$host" ]]; then
        echo "Checking certificate for $host..."
        echo | openssl s_client -connect "$host":443 -servername "$host" 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null || echo "Failed to connect or invalid cert"
    else
        echo "Usage: cert-check <hostname>"
        echo "Example: cert-check google.com"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION & DOTFILES
# ─────────────────────────────────────────────────────────────────────────────

# edit-config - Open ~/.bashrc, ~/.config, etc.
edit-config() {
    local editor="${EDITOR:-vim}"
    
    echo "Quick config editor:"
    echo "  1) ~/.bashrc"
    echo "  2) ~/.bash_profile_enhanced/bash_enhanced.sh"
    echo "  3) ~/.config"
    echo "  4) ~/.ssh/config"
    echo "  5) Custom file"
    echo ""
    read -rp "Select option: " opt
    
    case "$opt" in
        1) $editor ~/.bashrc ;;
        2) $editor ~/.bash_profile_enhanced/bash_enhanced.sh ;;
        3) $editor ~/.config ;;
        4) $editor ~/.ssh/config ;;
        5) read -rp "Enter file path: " fpath && $editor "$fpath" ;;
        *) echo "Invalid option" ;;
    esac
}

# dotfiles - Manage, sync, backup dotfiles
dotfiles() {
    local dotfiles_dir="$HOME/.dotfiles"
    
    case "${1:-status}" in
        backup|b)
            echo "Backing up dotfiles to $dotfiles_dir..."
            mkdir -p "$dotfiles_dir"
            cp -n ~/.bashrc ~/.bash_profile_enhanced "$dotfiles_dir/" 2>/dev/null || true
            echo "✓ Backup complete"
            ;;
        sync|s)
            echo "Syncing dotfiles..."
            [[ -d "$dotfiles_dir" ]] && cp "$dotfiles_dir"/* ~/ 2>/dev/null
            echo "✓ Sync complete"
            ;;
        status|"")
            echo "Dotfiles status:"
            [[ -d "$dotfiles_dir" ]] && echo "✓ Dotfiles directory exists" || echo "✗ No dotfiles directory"
            ;;
        *)
            echo "Usage: dotfiles [backup|sync|status]"
            ;;
    esac
}

# theme - Switch color schemes, prompts
theme() {
    echo "Color themes (placeholder - extend with your preferred themes)"
    echo "  1) Default (blue/cyan)"
    echo "  2) Dark"
    echo "  3) Light"
    echo ""
    read -rp "Select theme: " theme_num
    
    case "$theme_num" in
        1) echo "Using default theme" ;;
        2) echo "Dark theme selected" ;;
        3) echo "Light theme selected" ;;
        *) echo "Invalid selection" ;;
    esac
}

# keys - View, customize all bindings
keys() {
    echo "=== Key Bindings ==="
    echo ""
    echo "Readline bindings:"
    bind -l | head -20
    echo "... (use 'bind -l' for full list)"
    echo ""
    echo "X11/XKB layout:"
    localectl status 2>/dev/null | grep -i keyboard || echo "Not available"
}

# pkg-audit - List, update, audit installed packages
pkg-audit() {
    echo "=== Package Audit ==="
    echo ""
    
    # APT
    if _has apt; then
        echo "APT upgrades available:"
        apt list --upgradable 2>/dev/null | head -10 || echo "None or requires sudo"
        echo ""
    fi
    
    # npm
    if _has npm; then
        echo "npm outdated packages:"
        npm outdated 2>/dev/null | head -10 || echo "None"
        echo ""
    fi
    
    # pip
    if _has pip; then
        echo "pip outdated packages:"
        pip list --outdated 2>/dev/null | head -10 || echo "None or requires pip install --upgrade pip"
    fi
}

# sync-config - Push/pull config to remote
sync-config() {
    local remote="${1:-}"
    
    if [[ -z "$remote" ]]; then
        echo "Usage: sync-config <remote_url_or_host>"
        echo "Example: sync-config git@github.com:user/dotfiles.git"
        return 1
    fi
    
    local config_dir="$HOME/.bash_profile_enhanced"
    echo "Syncing config to $remote..."
    
    # Initialize git repo if needed
    if ! git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$config_dir" init
        git -C "$config_dir" add .
        git -C "$config_dir" commit -m "Initial config sync"
    fi
    
    # Add remote and push
    git -C "$config_dir" remote add origin "$remote" 2>/dev/null || git -C "$config_dir" remote set-url origin "$remote"
    git -C "$config_dir" push -u origin main 2>/dev/null || git -C "$config_dir" push -u master 2>/dev/null
    
    echo "✓ Sync complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# MONITORING & DIAGNOSTICS
# ─────────────────────────────────────────────────────────────────────────────

# bench - CPU, disk, network, memory benchmarks
bench() {
    echo "=== System Benchmarks ==="
    echo ""
    
    # CPU benchmark
    echo "CPU benchmark (sysbench)..."
    if _has sysbench; then
        sysbench cpu run 2>&1 | tail -5
    else
        echo "Install sysbench for CPU benchmark: sudo apt install sysbench"
    fi
    echo ""
    
    # Disk benchmark
    echo "Disk write benchmark..."
    dd if=/dev/zero of=/tmp/bench_test bs=1M count=100 2>&1 | tail -1
    rm -f /tmp/bench_test
}

# health - SMART, temps, fans, battery
health() {
    echo "=== System Health ==="
    echo ""
    
    # SMART status
    if _has smartctl; then
        echo "SMART Status:"
        smartctl -H /dev/sda 2>/dev/null || echo "smartctl not available or no /dev/sda"
        echo ""
    fi
    
    # Temperatures
    echo "Temperatures:"
    if _has sensors; then
        sensors 2>/dev/null | head -10 || echo "lm-sensors not configured"
    else
        cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | while read t; do echo "$((t/1000))°C"; done || echo "Not available"
    fi
    echo ""
    
    # Battery (if laptop)
    if [[ -d /sys/class/power_supply ]]; then
        echo "Battery:"
        for bat in /sys/class/power_supply/BAT*; do
            [[ -f "$bat/status" ]] && echo "  $(basename $bat): $(cat $bat/status) ($(cat $bat/capacity)%)"
        done
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# UTILITIES & EXTRAS
# ─────────────────────────────────────────────────────────────────────────────

# calc - bc, python, units conversion
calc() {
    local expr="$*"
    [[ -z "$expr" ]] && { echo "Usage: calc <expression>"; echo "Example: calc '2 + 2 * 2'"; return 1; }
    [[ "$expr" == "--help" || "$expr" == "-h" ]] && {
        cat <<'HELP'
Usage: calc <mathematical expression>

Perform mathematical calculations using bc or Python.

Supported operations:
  • Basic arithmetic: +, -, *, /, %
  • Exponentiation: ^ (use ** in Python)
  • Functions: sin(), cos(), sqrt(), log(), etc. (bc/math module)
  • Variables and expressions

Examples:
  calc "2 + 2 * 2"              # Returns: 6
  calc "100 / 7"                # Returns: 14.285714...
  calc "sqrt(144)"              # Returns: 12
  calc "2 ^ 10"                 # Returns: 1024
  calc "sin(0.5)"               # Returns: 0.479425...
HELP
        return 0
    }
    
    # Try bc first
    if _has bc; then
        echo "$expr = $(echo "$expr" | bc -l 2>/dev/null)"
    elif _has python3; then
        echo "$expr = $(python3 -c "print($expr)" 2>/dev/null)"
    else
        echo "Need bc or python3 for calculations"
    fi
}

# cal - Calendar with reminders
cal() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: cal [month] [year]       Display calendar

Arguments:
  month         Month number (1-12)
  year          Year number

Also shows reminders from ~/.reminders

Examples:
  cal                           # Current month
  cal 12 2024                   # December 2024
  cal 7 2025                    # July 2025
HELP
        return 0
    }
    command cal "$@"
    echo ""
    echo "Reminders:"
    [[ -f ~/.reminders ]] && cat ~/.reminders || echo "(no reminders)"
}

# encode - base64, url, html, rot13
encode() {
    local input="${2:-}"
    
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: encode <mode> [input]

Encode or decode text using various formats.

Modes:
  base64, b64      Base64 encode
  url, urle        URL encode
  rot13, r13       ROT13 cipher
  decode, d        Base64 decode

Input:
  Provide as argument or pipe to stdin

Examples:
  encode base64 "hello"         # Encode string
  encode url "hello world"      # URL encode
  encode rot13 "test"           # ROT13
  echo "abc" | encode base64    # Pipe input
  encode d "YWJj"               # Decode
HELP
        return 0
    }
    
    case "${1:-base64}" in
        base64|b64)
            [[ -n "$input" ]] && echo -n "$input" | base64 || cat | base64
            ;;
        url|urle)
            [[ -n "$input" ]] && python3 -c "import urllib.parse; print(urllib.parse.quote('$input'))" || cat | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read()))"
            ;;
        rot13|r13)
            [[ -n "$input" ]] && echo -n "$input" | tr 'A-Za-z' 'N-ZA-Mn-za-m' || cat | tr 'A-Za-z' 'N-ZA-Mn-za-m'
            ;;
        decode|d)
            echo -n "$input" | base64 -d
            ;;
        *)
            echo "Usage: encode [base64|url|rot13|decode] [input]"
            ;;
    esac
}

# random - UUID, password, dice, shuffle
random() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: random <type> [args]

Generate random values.

Types:
  uuid              Generate UUID v4
  password [len]    Generate password (default: 16 chars)
  dice [sides] [n]  Roll dice (default: d6, 1 roll)
  shuffle           Shuffle stdin lines

Examples:
  random uuid                     # Generate UUID
  random password 24              # 24-char password
  random dice 20 3                # Roll 3d20
  echo -e "a\nb\nc" | random      # Shuffle lines
HELP
        return 0
    }
    case "${1:-uuid}" in
        uuid)
            if _has uuidgen; then
                uuidgen
            else
                cat /proc/sys/kernel/random/uuid
            fi
            ;;
        pass|password)
            local len="${2:-16}"
            tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c "$len"
            echo
            ;;
        dice|die)
            local sides="${2:-6}"
            local count="${3:-1}"
            for ((i=0; i<count; i++)); do
                echo $((RANDOM % sides + 1))
            done
            ;;
        shuffle)
            shuf
            ;;
        *)
            echo "Usage: random [uuid|password|dice|shuffle]"
            echo "  random uuid              - Generate UUID"
            echo "  random password [len]    - Generate random password"
            echo "  random dice [sides] [n]  - Roll dice"
            echo "  random shuffle           - Shuffle stdin lines"
            ;;
    esac
}

# json-fmt - JSON formatting and manipulation
json-fmt() {
    local file="${1:-}"
    [[ -z "$file" ]] && { echo "Usage: json-fmt <file.json>"; return 1; }
    [[ "$file" == "--help" || "$file" == "-h" ]] && {
        cat <<'HELP'
Usage: json-fmt <file.json>

Format and pretty-print JSON files.

Arguments:
  file.json       JSON file to format

Output:
  Formatted JSON to stdout

Examples:
  json-fmt config.json          # Pretty print to stdout
  json-fmt data.json > out.json # Save formatted output
HELP
        return 0
    }
    python3 -m json.tool "$file" 2>/dev/null || jq . "$file" 2>/dev/null || echo "Need python3 or jq"
}

# json-lint - Lint JSON files
json-lint() {
    local file="${1:-}"
    [[ -z "$file" ]] && { echo "Usage: json-lint <file.json>"; return 1; }
    [[ "$file" == "--help" || "$file" == "-h" ]] && {
        cat <<'HELP'
Usage: json-lint <file.json>

Validate JSON syntax.

Arguments:
  file.json       JSON file to validate

Output:
  "Valid JSON" or error message

Examples:
  json-lint config.json         # Check if valid
  json-lint data.json && echo OK
HELP
        return 0
    }
    python3 -c "import json; json.load(open('$file'))" 2>&1 && echo "Valid JSON" || echo "Invalid JSON"
}

# json-get - Get value from JSON
json-get() {
    local file="${1:-}" key="${2:-}"
    [[ -z "$file" || -z "$key" ]] && { echo "Usage: json-get <file.json> <key>"; return 1; }
    [[ "$file" == "--help" || "$file" == "-h" ]] && {
        cat <<'HELP'
Usage: json-get <file.json> <key>

Extract a value from JSON file.

Arguments:
  file.json       JSON file
  key             Key path (e.g., 'name', 'user.id')

Output:
  Value of the specified key

Examples:
  json-get config.json name     # Get top-level key
  json-get data.json user.email # Get nested key
HELP
        return 0
    }
    jq ".$key" "$file" 2>/dev/null || python3 -c "import json,sys; d=json.load(open('$file')); print(d.get('$key'))" 2>/dev/null
}

# json-set - Set value in JSON
json-set() {
    local file="${1:-}" key="${2:-}" value="${3:-}"
    [[ -z "$file" || -z "$key" || -z "$value" ]] && { echo "Usage: json-set <file.json> <key> <value>"; return 1; }
    [[ "$file" == "--help" || "$file" == "-h" ]] && {
        cat <<'HELP'
Usage: json-set <file.json> <key> <value>

Set a value in JSON file (modifies in place).

Arguments:
  file.json       JSON file to modify
  key             Key path (e.g., 'name', 'user.id')
  value           New value (string)

Examples:
  json-set config.json name "new"   # Set string value
  json-set data.json count 42       # Set number
HELP
        return 0
    }
    jq ".$key = \"$value\"" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# py-fmt - Python formatting with black/ruff
py-fmt() {
    local dir="${1:-.}"
    [[ "$dir" == "--help" || "$dir" == "-h" ]] && {
        cat <<'HELP'
Usage: py-fmt [directory]

Format Python files using black or ruff.

Arguments:
  directory       Directory to format (default: current)

Tools:
  • black         Standard Python formatter
  • ruff          Fast Python linter/formatter

Examples:
  py-fmt                      # Format current dir
  py-fmt /path/to/project     # Format specific dir
  py-fmt .                    # Same as default
HELP
        return 0
    }
    cd "$dir" || return 1
    if _has black; then
        echo "Formatting Python files with black..."
        black . 2>&1 | tail -5
    elif _has ruff; then
        echo "Formatting Python files with ruff..."
        ruff format . 2>&1 | tail -5
    else
        echo "Install black or ruff for Python formatting"
    fi
}

# py-lint - Python linting with ruff/flake8
py-lint() {
    local dir="${1:-.}"
    [[ "$dir" == "--help" || "$dir" == "-h" ]] && {
        cat <<'HELP'
Usage: py-lint [directory]

Lint Python files using ruff or flake8.

Arguments:
  directory       Directory to lint (default: current)

Tools:
  • ruff          Fast Python linter
  • flake8        Classic Python linter

Examples:
  py-lint                     # Lint current dir
  py-lint /path/to/project    # Lint specific dir
HELP
        return 0
    }
    cd "$dir" || return 1
    if _has ruff; then
        echo "Linting with ruff..."
        ruff check . 2>&1 | tail -10
    elif _has flake8; then
        echo "Linting with flake8..."
        flake8 . 2>&1 | tail -10
    else
        echo "Install ruff or flake8 for Python linting"
    fi
}

# find-dupes - Find duplicate files by size/hash
find-dupes() {
    local dir="${1:-.}" max_depth="${2:-3}"
    [[ "$dir" == "--help" || "$dir" == "-h" ]] && {
        cat <<'HELP'
Usage: find-dupes <directory> [max_depth]

Find duplicate files using MD5 hash comparison.

Arguments:
  directory       Directory to scan (default: current)
  max_depth       Maximum directory depth (default: 3)

Output:
  Lists paths of duplicate files

Examples:
  find-dupes .                    # Scan current dir
  find-dupes /data 5              # Scan with depth 5
  find-dupes ~/projects           # Scan projects folder
HELP
        return 0
    }
    cd "$dir" || return 1
    
    echo "Finding duplicates in $dir (max depth: $max_depth)..."
    find . -maxdepth "$max_depth" -type f -exec md5sum {} \; 2>/dev/null | \
        sort | uniq -w32 -D | cut -d' ' -f3- | sort | uniq -d
}

# compress - Compress files/dirs with smart excludes
compress() {
    local target="${1:-}" algo="${2:-gzip}" out="${3:-}"
    
    [[ "$target" == "--help" || "$target" == "-h" ]] && {
        cat <<'HELP'
Usage: compress <path> [algo] [output] [options]

Compress a file or directory with automatic format detection.

Arguments:
  path          File or directory to compress
  algo          Compression algorithm: gzip, bzip2, xz, zip (default: gzip)
  output        Output filename (default: path.algo)

Options:
  --help, -h    Show this help message
  --fast        Use fastest compression (gzip only)
  --best        Use best compression (xz)
  --no-excludes Don't exclude node_modules, .git, __pycache__

Examples:
  compress mydir                 # Creates mydir.tar.gz
  compress mydir zip             # Creates mydir.zip
  compress myfile.tar.xz         # Creates myfile.tar.xz.bz2
  compress data --best           # Uses xz for best compression
HELP
        return 0
    }
    
    [[ -z "$target" ]] && { echo "Usage: compress <path> [algo|gzip] [output]"; return 1; }
    [[ ! -e "$target" ]] && { echo "Error: $target not found"; return 1; }
    
    local basename=$(basename "$target")
    out="${out:-${basename}.${algo}}"
    
    case "$algo" in
        gzip|gz) tar -czf "$out" "$target" --exclude='node_modules' --exclude='.git' --exclude='__pycache__' 2>&1 ;;
        bzip2|bz2) tar -cjf "$out" "$target" --exclude='node_modules' --exclude='.git' --exclude='__pycache__' 2>&1 ;;
        xz|xz) tar -cJf "$out" "$target" --exclude='node_modules' --exclude='.git' --exclude='__pycache__' 2>&1 ;;
        zip) zip -r "$out" "$target" -x "*.git*" "*node_modules*" "*__pycache__*" 2>&1 ;;
        *) echo "Unknown algorithm: $algo"; return 1 ;;
    esac
    
    [[ $? -eq 0 ]] && echo "✓ Created $out" || echo "✗ Compression failed"
}

# test-archive - Verify archive integrity
test-archive() {
    local archive="${1:-}"
    [[ "$archive" == "--help" || "$archive" == "-h" ]] && {
        cat <<'HELP'
Usage: test-archive <archive_file>

Verify archive integrity without extracting.

Supported formats:
  .tar.gz, .tgz      gzip compressed tar
  .tar.bz2, .tbz2    bzip2 compressed tar
  .tar.xz, .txz      xz compressed tar
  .zip               zip archive

Examples:
  test-archive backup.tar.gz      # Check tar.gz
  test-archive data.zip           # Check zip
  test-archive archive.tar.xz     # Check xz
HELP
        return 0
    }
    [[ -z "$archive" ]] && { echo "Usage: test-archive <file.tar.gz|file.zip>"; return 1; }
    [[ ! -f "$archive" ]] && { echo "Error: $archive not found"; return 1; }
    
    case "$archive" in
        *.tar.gz|*.tgz) tar -tzf "$archive" >/dev/null 2>&1 && echo "Valid tar.gz" || echo "Invalid tar.gz" ;;
        *.tar.bz2|*.tbz2) tar -tjf "$archive" >/dev/null 2>&1 && echo "Valid tar.bz2" || echo "Invalid tar.bz2" ;;
        *.tar.xz|*.txz) tar -tJf "$archive" >/dev/null 2>&1 && echo "Valid tar.xz" || echo "Invalid tar.xz" ;;
        *.zip) unzip -t "$archive" >/dev/null 2>&1 && echo "Valid zip" || echo "Invalid zip" ;;
        *) echo "Unknown archive format"; return 1 ;;
    esac
}

# backup - Timestamped backup with retention
backup() {
    local source="${1:-}" dest="${2:-}"
    [[ "$source" == "--help" || "$source" == "-h" ]] && {
        cat <<'HELP'
Usage: backup <source> [destination]

Create timestamped compressed backup of file or directory.

Arguments:
  source          File or directory to backup
  destination     Backup destination (default: ~/backups)

Output:
  Creates: destination/source_YYYYMMDD_HHMMSS.tar.gz

Examples:
  backup myproject                  # To ~/backups/
  backup data /mnt/usb              # To USB drive
  backup config.yaml /tmp           # Single file backup
HELP
        return 0
    }
    
    [[ -z "$source" ]] && { echo "Usage: backup <source> [destination]"; return 1; }
    [[ ! -e "$source" ]] && { echo "Error: $source not found"; return 1; }
    
    dest="${dest:-$HOME/backups}"
    mkdir -p "$dest"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local basename=$(basename "$source")
    local backup_file="$dest/${basename}_${timestamp}.tar.gz"
    
    echo "Backing up $source to $backup_file..."
    tar -czf "$backup_file" "$source" --exclude='node_modules' --exclude='.git' --exclude='__pycache__' 2>&1
    
    [[ $? -eq 0 ]] && echo "✓ Backup created: $backup_file" || echo "✗ Backup failed"
}

# dps - Docker container status (wrapper around docker ps)
dps() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: dps              List all containers (running and stopped)

Show Docker containers with name, status, ports, and image.

Equivalent to: docker ps -a --format "table {{.Names}}\t{{.Status}}..."

Examples:
  dps                   # List all containers
  docker ps             # Same as dps
  docker ps -a          # Show stopped containers too
HELP
        return 0
    }
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"
}

# dtop - Docker top processes
dtop() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: dtop             Live container resource statistics

Show real-time CPU, memory, network, and disk usage per container.

Equivalent to: docker stats --no-stream

Examples:
  dtop                  # One-shot stats for all containers
  docker stats          # Continuous stats (Ctrl-C to stop)
HELP
        return 0
    }
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
}

# dlogs - Docker logs
dlogs() {
    local container="${1:-}" lines="${2:-50}"
    [[ "$container" == "--help" || "$container" == "-h" ]] && {
        cat <<'HELP'
Usage: dlogs <container> [lines]

View logs from a Docker container.

Arguments:
  container     Container name or ID
  lines         Number of lines to show (default: 50)

Examples:
  dlogs myapp           # Last 50 lines
  dlogs myapp 200       # Last 200 lines
  docker logs -f myapp  # Follow logs (continuous)
HELP
        return 0
    }
    [[ -z "$container" ]] && { echo "Usage: dlogs <container> [lines]"; return 1; }
    docker logs --tail "$lines" "$container" 2>&1
}

# dshell - Docker shell into container
dshell() {
    local container="${1:-}"
    [[ "$container" == "--help" || "$container" == "-h" ]] && {
        cat <<'HELP'
Usage: dshell <container>

Open interactive shell in a Docker container.

Arguments:
  container     Container name or ID

Examples:
  dshell myapp          # Shell into container
  docker exec -it myapp bash
HELP
        return 0
    }
    [[ -z "$container" ]] && { echo "Usage: dshell <container>"; return 1; }
    docker exec -it "$container" sh 2>/dev/null || docker exec -it "$container" bash 2>/dev/null
}

# dstop - Stop containers
dstop() {
    local container="${1:-}"
    [[ "$container" == "--help" || "$container" == "-h" ]] && {
        cat <<'HELP'
Usage: dstop <container>

Stop a running Docker container gracefully.

Arguments:
  container     Container name or ID

Examples:
  dstop myapp           # Stop container
  docker stop myapp
HELP
        return 0
    }
    [[ -z "$container" ]] && { echo "Usage: dstop <container>"; return 1; }
    docker stop "$container"
}

# dstart - Start containers
dstart() {
    local container="${1:-}"
    [[ "$container" == "--help" || "$container" == "-h" ]] && {
        cat <<'HELP'
Usage: dstart <container>

Start a stopped Docker container.

Arguments:
  container     Container name or ID

Examples:
  dstart myapp          # Start container
  docker start myapp
HELP
        return 0
    }
    [[ -z "$container" ]] && { echo "Usage: dstart <container>"; return 1; }
    docker start "$container"
}

# drm - Remove containers
drm() {
    local container="${1:-}"
    [[ "$container" == "--help" || "$container" == "-h" ]] && {
        cat <<'HELP'
Usage: drm <container>

Remove a stopped Docker container.

Arguments:
  container     Container name or ID

Examples:
  drm myapp             # Remove stopped container
  docker rm myapp
  docker rm -f myapp    # Force remove running container
HELP
        return 0
    }
    [[ -z "$container" ]] && { echo "Usage: drm <container>"; return 1; }
    docker rm "$container"
}

# dimages - List Docker images
dimages() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: dimages          List all Docker images

Show repository, tag, ID, size, and creation date.

Equivalent to: docker images --format "table..."

Examples:
  dimages               # List all images
  docker images         # Same as dimages
  docker image ls       # Alternative syntax
HELP
        return 0
    }
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedAt}}"
}

# dvolumes - List Docker volumes
dvolumes() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: dvolumes         List all Docker volumes

Show volume names, drivers, and scope.

Equivalent to: docker volume ls

Examples:
  dvolumes              # List all volumes
  docker volume ls      # Same as dvolumes
HELP
        return 0
    }
    docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
}

# dnetworks - List Docker networks
dnetworks() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: dnetworks        List all Docker networks

Show network names, drivers, and scope.

Equivalent to: docker network ls

Examples:
  dnetworks             # List all networks
  docker network ls     # Same as dnetworks
HELP
        return 0
    }
    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
}

# dcompose - Docker compose operations
dcompose() {
    local action="${1:-ps}" args="${@:2}"
    [[ "$action" == "--help" || "$action" == "-h" ]] && {
        cat <<'HELP'
Usage: dcompose <action> [args]

Docker Compose operations.

Actions:
  up              Start services (docker compose up)
  down            Stop and remove services (docker compose down)
  logs            View service logs (docker compose logs)
  ps              List running services (docker compose ps)
  build           Build or rebuild services (docker compose build)
  pull            Pull service images (docker compose pull)
  restart         Restart services (docker compose restart)

Examples:
  dcompose up                 # Start all services
  dcompose up -d              # Start in background
  dcompose down               # Stop all services
  dcompose logs web           # View web service logs
  dcompose build              # Rebuild all services
HELP
        return 0
    }
    case "$action" in
        up) docker compose up $args ;;
        down) docker compose down $args ;;
        logs) docker compose logs $args ;;
        ps) docker compose ps $args ;;
        build) docker compose build $args ;;
        *) echo "Usage: dcompose [up|down|logs|ps|build] [args]" ;;
    esac
}

# dprune - Prune Docker resources
dprune() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: dprune                 Clean unused Docker resources

Removes:
  • Stopped containers
  • Dangling images
  • Unused volumes
  • Build cache

Warning: This operation is irreversible!

Examples:
  dprune                      # Clean all unused resources
HELP
        return 0
    }
    echo "Pruning Docker system..."
    docker system prune -f 2>&1
    docker volume prune -f 2>&1
    docker image prune -af 2>&1
}

# keystore-list - List EVM keystores
keystore-list() {
    local keystore_dir="${KESTORE_DIR:-$HOME/.keystores}"
    [[ ! -d "$keystore_dir" ]] && { echo "No keystore directory at $keystore_dir"; return 1; }
    
    echo "Keystores in $keystore_dir:"
    ls -1 "$keystore_dir"/*.json 2>/dev/null | while read -r keyfile; do
        local name=$(basename "$keyfile" .json)
        local addr=$(python3 -c "import json; print(json.load(open('$keyfile'))['address'])" 2>/dev/null || echo "unknown")
        echo "  $name -> $addr"
    done
}

# git-stats - Git repository statistics
git-stats() {
    local dir="${1:-.}"
    cd "$dir" || return 1
    
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Not a git repository"
        return 1
    fi
    
    echo "=== Git Repository Statistics ==="
    echo ""
    echo "Contributors:"
    git shortlog -sn | head -10
    echo ""
    echo "Recent activity (last 30 days):"
    git log --since="30 days ago" --oneline | wc -l
    echo " commits"
    echo ""
    echo "Largest files:"
    git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | awk '/^blob/ {print $3, $4}' | sort -rn | head -5 | numfmt --field=1 --to=iec 2>/dev/null || git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | awk '/^blob/ {print $3, $4}' | sort -rn | head -5
}

# units - Unit conversion
units() {
    if _has units; then
        units "$@"
    else
        echo "Install 'units' package: sudo apt install units"
        echo "Example: units '100 miles' 'km'"
    fi
}

# web - HTTP helpers
web() {
    local method="${1:-GET}" url="${2:-}"
    
    [[ -z "$url" ]] && { echo "Usage: web [GET|POST|PUT|DELETE] <url>"; return 1; }
    
    case "$method" in
        GET|get)
            if _has http; then http "$url"; else curl -s "$url"; fi
            ;;
        POST|post)
            if _has http; then http POST "$url"; else curl -s -X POST "$url"; fi
            ;;
        PUT|put)
            if _has http; then http PUT "$url"; else curl -s -X PUT "$url"; fi
            ;;
        DELETE|delete)
            if _has http; then http DELETE "$url"; else curl -s -X DELETE "$url"; fi
            ;;
        *)
            echo "Unknown method: $method"
            ;;
    esac
}

# notes - Quick markdown notes, search
notes() {
    local notes_dir="$HOME/.notes"
    mkdir -p "$notes_dir"
    
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: notes <command> [args]

Quick markdown notes in ~/.notes directory.

Commands:
  new <title>     Create new note
  list            List all notes (default)
  search <query>  Search notes
  open <title>    Open note in editor

Examples:
  notes new "Meeting notes"       # Create note
  notes                           # List notes
  notes search "todo"             # Search for "todo"
  notes open "Meeting notes"      # Open note
HELP
        return 0
    }
    
    case "${1:-list}" in
        new|n)
            shift
            local title="${1:-untitled}"
            local note_file="$notes_dir/${title// /_}.md"
            echo "# $title" > "$note_file"
            echo "" >> "$note_file"
            ${EDITOR:-vim} "$note_file"
            echo "✓ Created: $note_file"
            ;;
        list|l|"")
            echo "=== Notes ==="
            ls -1 "$notes_dir"/*.md 2>/dev/null | xargs -I{} basename {} .md || echo "(no notes)"
            ;;
        search|s)
            shift
            grep -r "$*" "$notes_dir" 2>/dev/null || echo "No matches"
            ;;
        open|o)
            shift
            local title="${1:-}"
            [[ -z "$title" ]] && { echo "Usage: notes open <title>"; return 1; }
            ${EDITOR:-vim} "$notes_dir/${title// /_}.md"
            ;;
        *)
            echo "Usage: notes [new|list|search|open] [args]"
            ;;
    esac
}

# timer - Countdown, stopwatch, pomodoro
timer() {
    local action="${1:-help}"
    shift
    
    case "$action" in
        countdown|cd)
            local seconds="${1:-60}"
            echo "Countdown: $seconds seconds"
            for ((i=seconds; i>0; i--)); do
                printf "\r%3d" $i
                sleep 1
            done
            echo -e "\rDone!  "
            ;;
        pomodoro|pomo)
            local work="${1:-25}"
            local break_time="${2:-5}"
            echo "Pomodoro: ${work}m work, ${break_time}m break"
            echo "Starting work session..."
            sleep "$((work * 60))"
            echo "Work done! Take a ${break_time} minute break."
            sleep "$((break_time * 60))"
            echo "Break over!"
            ;;
        help|"")
            echo "Usage: timer [countdown|pomodoro] [args]"
            echo "  timer countdown <seconds>  - Countdown timer"
            echo "  timer pomodoro [work] [break] - Pomodoro timer"
            ;;
        *)
            echo "Unknown action: $action"
            ;;
    esac
}
