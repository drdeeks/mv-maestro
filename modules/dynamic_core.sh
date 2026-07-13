#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════════
# Dynamic Core Module — Auto-adapting, tool-aware, zero-config utilities
# Source from ~/.bashrc:  source ~/MV-Maestro/modules/dynamic_core.sh
# ════════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# COLORS & CONSTANTS (idempotent)
# ─────────────────────────────────────────────────────────────────────────────
# Only declare if not already set (allows safe re-sourcing)
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${BLUE:=\033[0;34m}"
: "${CYAN:=\033[0;36m}"
: "${BOLD:=\033[1m}"
: "${DIM:=\033[2m}"
: "${NC:=\033[0m}"

# ─────────────────────────────────────────────────────────────────────────────
# CORE UTILITIES
# ─────────────────────────────────────────────────────────────────────────────
_has() { command -v "$1" >/dev/null 2>&1; }

_die() { echo -e "${RED}✗${NC} $*" >&2; return 1; }
_ok()  { echo -e "${GREEN}✓${NC} $*"; }
_info() { echo -e "${BLUE}ℹ${NC} $*"; }
_warn() { echo -e "${YELLOW}⚠${NC} $*"; }

_spin() {
    local pid=$1 msg=${2:-Working} spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${NC} %s" "${spin:i++%${#spin}:1}" "$msg"
        sleep 0.08
    done
    wait "$pid" 2>/dev/null
    local rc=$?
    printf "\r  %s %s\n" "$( ((rc==0)) && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}" )" "$msg"
    return $rc
}

# Auto-detect best available compression tool
_best_compress() {
    _has zstd && { echo "zstd"; return; }
    _has gzip && { echo "gzip"; return; }
    _has xz && { echo "xz"; return; }
    _has lz4 && { echo "lz4"; return; }
    _has bzip2 && { echo "bzip2"; return; }
    echo "gzip"
}

# Smart excludes for developer directories
_DEV_EXCLUDES=(
    node_modules __pycache__ .git .hg .svn
    dist build target .next .cache .turbo .vercel
    vendor *.egg-info .venv venv env .env*
    .DS_Store Thumbs.db *.log *.tmp *.swp *~
    coverage .nyc_output .pytest_cache .mypy_cache
    .idea .vscode *.iml *.sublime-*
)

# ─────────────────────────────────────────────────────────────────────────────
# ENCRYPTION — age (preferred) / gpg fallback, auto-detect
# ─────────────────────────────────────────────────────────────────────────────

_enc_tool() { _has age && { echo "age"; return; } || _has gpg && { echo "gpg"; return; } || return 1; }

_enc_tool_symmetric() { _has gpg && { echo "gpg"; return; } || _has age && { echo "age"; return; } || return 1; }

# encrypt <path> [recipient|passphrase] [--armor] [--sign]
encrypt() {
    [[ $# -eq 0 ]] && { echo "encrypt <path> [recipient] [--armor] [--sign] [--passphrase]"; return 1; }
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: encrypt <path> [options] [recipient]

Encrypt files or directories using age or GPG.

Arguments:
  path          File or directory to encrypt
  recipient     Recipient's age public key (optional)

Options:
  --armor       Output ASCII-armored format
  --sign        Sign with GPG (GPG mode only)
  --passphrase  Use passphrase mode explicitly
  --help, -h    Show this help message

Environment:
  AGE_PASSPHRASE    Passphrase for symmetric encryption

Encryption modes:
  • With recipient: age asymmetric encryption (requires 'age')
  • Without recipient: GPG/age symmetric encryption with passphrase
  • Directories are automatically archived as tar.gz before encryption

Examples:
  encrypt secret.txt                          # Symmetric (gpg/age)
  encrypt config.yaml user@example.age        # Asymmetric (age)
  encrypt mydir --armor                       # Create .asc file
  encrypt data.tar.gz --sign                  # Sign + encrypt
HELP
        return 0
    }
    
    local src=$(realpath "$1"); shift
    [[ ! -e $src ]] && { _die "Not found: $src"; return 1; }

    local recipient="" armor=0 sign=0 passphrase_mode=0
    while [[ $# -gt 0 ]]; do
        case $1 in
            --armor) armor=1; shift ;;
            --sign) sign=1; shift ;;
            --passphrase) passphrase_mode=1; shift ;;
            -*) _die "Unknown flag: $1"; return 1 ;;
            *) recipient=$1; shift ;;
        esac
    done

    local out tool
    if [[ -n $recipient ]]; then
        tool=$(_enc_tool) || { _die "Need 'age' for recipient encryption"; return 1; }
    elif (( passphrase_mode )); then
        tool=$(_enc_tool_symmetric) || { _die "Need 'gpg' or 'age'"; return 1; }
    else
        tool=$(_enc_tool_symmetric) || { _die "Need 'gpg' or 'age'"; return 1; }
    fi

    if [[ -d $src ]]; then
        out="${src}.tar.${tool}"
        _info "Encrypting directory ${BOLD}$src${NC} → ${BOLD}$out${NC} ($tool)"
        if [[ $tool == "age" ]]; then
            if [[ -n $recipient ]]; then
                tar -czf - -C "$(dirname "$src")" "$(basename "$src")" \
                    | age -e -r "$recipient" ${armor:+-a} -o "$out"
            else
                tar -czf - -C "$(dirname "$src")" "$(basename "$src")" \
                    | age -e -p ${armor:+-a} -o "$out"
            fi
        else
            local gpg_sign=() gpg_batch=()
            (( sign )) && gpg_sign=(--sign)
            (( passphrase_mode )) && gpg_batch=(--batch --yes --passphrase "$AGE_PASSPHRASE")
            
            tar -czf - -C "$(dirname "$src")" "$(basename "$src")" \
                | gpg --symmetric --cipher AES256 ${armor:+--armor} "${gpg_sign[@]}" "${gpg_batch[@]}" -o "$out"
        fi
    else
        out="${src}.${tool}"
        _info "Encrypting file ${BOLD}$src${NC} → ${BOLD}$out${NC} ($tool)"
        if [[ $tool == "age" ]]; then
            if [[ -n $recipient ]]; then
                age -e -r "$recipient" ${armor:+-a} -o "$out" "$src"
            else
                age -e -p ${armor:+-a} -o "$out" "$src"
            fi
        else
            local gpg_sign=() gpg_batch=()
            (( sign )) && gpg_sign=(--sign)
            (( passphrase_mode )) && gpg_batch=(--batch --yes --passphrase "$AGE_PASSPHRASE")
            
            gpg --symmetric --cipher AES256 ${armor:+--armor} "${gpg_sign[@]}" "${gpg_batch[@]}" -o "$out" "$src"
        fi
    fi
    _ok "Encrypted: $out"
}

# decrypt <file.age|file.gpg> [dest] [--passphrase]
decrypt() {
    [[ $# -eq 0 ]] && { echo "decrypt <file.age|file.gpg> [dest] [--passphrase]"; return 1; }
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: decrypt <encrypted_file> [destination] [options]

Decrypt age or GPG encrypted files.

Arguments:
  encrypted_file    File to decrypt (.age or .gpg)
  destination       Output directory (default: current dir)

Options:
  --passphrase      Use passphrase mode (for symmetric encryption)
  --help, -h        Show this help message

Environment:
  AGE_PASSPHRASE    Passphrase for symmetric decryption

Examples:
  decrypt secret.txt.age                    # Decrypt to current dir
  decrypt config.yaml.gpg /tmp/             # Decrypt to /tmp/
  decrypt data.tar.gz.age --passphrase      # Explicit passphrase mode
HELP
        return 0
    }
    
    local src=$(realpath "$1"); shift
    local dest="." passphrase_mode=0
    while [[ $# -gt 0 ]]; do
        case $1 in
            --passphrase) passphrase_mode=1; shift ;;
            -*) _die "Unknown flag: $1"; return 1 ;;
            *) dest=$1; shift ;;
        esac
    done
    [[ ! -f $src ]] && { _die "Not found: $src"; return 1; }
    mkdir -p "$dest"

    if [[ $src == *.age ]]; then
        if [[ $src == *.tar.age ]]; then
            age -d "$src" | tar -xzf - -C "$dest"
        else
            age -d -o "$dest/$(basename "$src" .age)" "$src"
        fi
    elif [[ $src == *.gpg ]]; then
        local gpg_batch=()
        (( passphrase_mode )) && gpg_batch=(--batch --yes --passphrase "$AGE_PASSPHRASE")
        if [[ $src == *.tar.gpg ]]; then
            gpg -d "${gpg_batch[@]}" "$src" | tar -xzf - -C "$dest"
        else
            gpg -d "${gpg_batch[@]}" -o "$dest/$(basename "$src" .gpg)" "$src"
        fi
    else
        _die "Unknown encrypted format: $src"; return 1
    fi
    _ok "Decrypted to: $dest"
}

# ─────────────────────────────────────────────────────────────────────────────
# SSH CONFIG — dynamic generator with Tailscale, includes, templates
# ─────────────────────────────────────────────────────────────────────────────
_ssh_dir="$HOME/.ssh"
_ssh_config_d="$_ssh_dir/config.d"
mkdir -p "$_ssh_config_d" && chmod 700 "$_ssh_dir" "$_ssh_config_d"

# Ensure main config includes config.d
grep -q "Include config.d/*" "$_ssh_dir/config" 2>/dev/null || echo -e "\nInclude config.d/*" >> "$_ssh_dir/config"

# ssh-add-key [alias] — interactive key setup + config entry
ssh-add-key() {
    local alias=${1:-}
    [[ -z $alias ]] && { read -rp "Host alias: " alias; [[ -z $alias ]] && return 1; }

    local file="$_ssh_config_d/${alias}.conf"
    [[ -f $file ]] && { _warn "Exists: $file"; read -rp "Overwrite? [y/N] " ans; [[ $ans =~ ^[Yy] ]] || return; }

    local hostname user port key identity extra ts
    read -rp "Hostname/IP: " hostname
    read -rp "User: " user
    read -rp "Port [22]: " port; port=${port:-22}
    read -rp "IdentityFile [~/.ssh/id_ed25519]: " key; key=${key:-~/.ssh/id_ed25519}
    read -rp "Extra options (ProxyJump, ForwardAgent, etc): " extra
    read -rp "Tailscale variant? [y/N]: " ts

    cat > "$file" <<EOF
# $alias — generated $(date)
Host $alias
    HostName $hostname
    User $user
    Port $port
    IdentityFile $key
    ${extra:-# No extra options}
EOF

    if [[ $ts =~ ^[Yy] ]]; then
        local ts_host="${hostname}.ts.net"
        cat >> "$file" <<EOF

Host ${alias}-ts
    HostName $ts_host
    User $user
    Port $port
    IdentityFile $key
    ${extra:-# No extra options}
EOF
        _ok "Added Tailscale variant: ${alias}-ts → $ts_host"
    fi

    chmod 600 "$file"
    _ok "Created: $file"
    _info "Test: ssh $alias"
}

# ssh-list — pretty list all configured hosts
ssh-list() {
    echo -e "${BOLD}${CYAN}SSH Hosts:${NC}"
    for f in "$_ssh_config_d"/*.conf; do
        [[ -f $f ]] || continue
        awk '
            /^Host / && !/[\*\?]/ { host=$2 }
            /^[[:space:]]*HostName/ { hn=$2 }
            /^[[:space:]]*User/ { u=$2 }
            /^[[:space:]]*Port/ { p=$2 }
            /^[[:space:]]*IdentityFile/ { key=$2 }
            END { if(host) printf "  \033[0;32m%-20s\033[0m %s@%s:%s  (%s)\n", host, u?u:"?", hn?hn:"?", p?p:"22", key?key:"default" }
        ' "$f"
    done
}

# ssh-test <alias> — test connection with verbose output
ssh-test() { [[ -z $1 ]] && { echo "Usage: ssh-test <alias>"; return 1; }; ssh -o ConnectTimeout=5 -o BatchMode=yes "$1" true && _ok "Connected to $1" || _die "Failed: $1"; }

# ssh-copy-id-auto <alias> — copy key to remote using configured IdentityFile
ssh-copy-id-auto() {
    [[ -z $1 ]] && { echo "Usage: ssh-copy-id-auto <alias>"; return 1; }
    local key=$(_get_identity "$1") || return 1
    ssh-copy-id -i "$key" "$1"
}

_get_identity() {
    local f="$_ssh_config_d/$1.conf"
    [[ -f $f ]] || { _die "Host not found: $1"; return 1; }
    awk '/^[[:space:]]*IdentityFile/ {print $2; exit}' "$f"
}

# ─────────────────────────────────────────────────────────────────────────────
# TAILSCALE — dynamic helpers
# ─────────────────────────────────────────────────────────────────────────────
ts-up() {
    local args=("--ssh" "--advertise-routes=$(ip route | awk '!/default/ {print $1}' | paste -sd,)")
    _has tailscale || { _die "tailscale not installed"; return 1; }
    sudo tailscale up "${args[@]}" "$@"
}

ts-ssh() { [[ -z $1 ]] && { echo "Usage: ts-ssh <hostname>"; return 1; }; ssh "$1"; }
ts-funnel() { [[ -z $1 ]] && { echo "Usage: ts-funnel <port> [protocol]"; return 1; }; tailscale funnel "${2:-tcp}:$1"; }
ts-serve() { [[ -z $1 ]] && { echo "Usage: ts-serve <port> [path]"; return 1; }; tailscale serve "${2:-/}" "http://localhost:$1"; }
ts-status() { tailscale status --json | jq -r '.Peer[] | "\(.HostName)\t\(.TailscaleIPs[0])\t\(.Online)"' | column -t; }

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDFLARE — requires CF_API_TOKEN, CF_ACCOUNT_ID, CF_ZONE_ID
# ─────────────────────────────────────────────────────────────────────────────
_cf_api() { [[ -z $CF_API_TOKEN ]] && { _die "Set CF_API_TOKEN"; return 1; }; curl -s -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" "$@"; }

cf-dns-list() { [[ -z $1 ]] && { echo "Usage: cf-dns-list <zone_id>"; return 1; }; _cf_api "https://api.cloudflare.com/client/v4/zones/$1/dns_records" | jq -r '.result[] | "\(.type)\t\(.name)\t\(.content)\t\(.proxied)"' | column -t; }

cf-dns-add() {
    [[ $# -lt 4 ]] && { echo "cf-dns-add <zone_id> <type> <name> <content> [--proxied]"; return 1; }
    local proxied=false; [[ $5 == "--proxied" ]] && proxied=true
    _cf_api -X POST "https://api.cloudflare.com/client/v4/zones/$1/dns_records" \
        -d "{\"type\":\"$2\",\"name\":\"$3\",\"content\":\"$4\",\"proxied\":$proxied}" | jq
}

cf-tunnel-create() { [[ -z $1 ]] && { echo "cf-tunnel-create <name>"; return 1; }; cloudflared tunnel create "$1"; }
cf-tunnel-route() { [[ $# -lt 3 ]] && { echo "cf-tunnel-route <tunnel> <hostname> <service>"; return 1; }; cloudflared tunnel route dns "$1" "$2" --service "$3"; }
cf-tunnel-run() { [[ -z $1 ]] && { echo "cf-tunnel-run <tunnel>"; return 1; }; cloudflared tunnel run "$1"; }
cf-cache-purge() { [[ -z $1 ]] && { echo "cf-cache-purge <zone_id> [urls...]"; return 1; }; local urls=${2:-[\"*\"]}; _cf_api -X POST "https://api.cloudflare.com/client/v4/zones/$1/purge_cache" -d "{\"files\":$urls}" | jq; }

# ─────────────────────────────────────────────────────────────────────────────
# GIT — enhanced, repo-aware
# ─────────────────────────────────────────────────────────────────────────────
git-root() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: git-root               CD to git repo root

Output:
  Prints and changes to repository root directory

Examples:
  git-root                    # CD to current repo root
  $(git-root)                 # Get path without changing dir
HELP
        return 0
    }
    git rev-parse --show-toplevel 2>/dev/null && cd "$_" || _die "Not a git repo"
}

git-recent() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: git-recent [count]

Show recent git branches sorted by last commit.

Arguments:
  count         Number of branches (default: 15)

Output:
  Branch name | date | author | subject

Examples:
  git-recent                  # Show 15 recent branches
  git-recent 5                # Show 5 recent branches
HELP
        return 0
    }
    local n=${1:-15}
    git for-each-ref --sort=-committerdate --format='%(refname:short)|%(committerdate:short)|%(authorname)|%(subject)' refs/heads | head -n "$n" | column -t -s'|'
}

git-wip() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: git-wip                Quick WIP commit

Commits all staged and unstaged changes with "wip:" message.

Examples:
  git-wip                     # Commit current work
  git                         # Alias for git-wip
HELP
        return 0
    }
    git add -A && git commit -m "wip: $(date '+%Y-%m-%d %H:%M')"
}

git-unwip() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: git-unwip              Undo last WIP commit

Resets last commit if it was a wip commit. Preserves changes in working dir.

Examples:
  git-unwip                   # Undo last wip commit
HELP
        return 0
    }
    git log -1 --format=%s | grep -q "^wip:" && git reset HEAD~1 || _warn "Last commit not a wip"
}

git-standup() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: git-standup [days]

Show your commits across all projects in ~/projects.

Arguments:
  days          Lookback period (default: 7)

Output:
  Project: commit messages

Examples:
  git-standup                 # Last 7 days
  git-standup 30              # Last 30 days
HELP
        return 0
    }
    local days=${1:-7} author=$(git config user.email)
    find ~/projects -name .git -type d -prune -execdir sh -c '
        git log --since="'"$days"' days ago" --author="'"$author"'" --oneline 2>/dev/null | sed "s/^/$(basename $(pwd)): /"
    ' \;
}

git-prune() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: git-prune              Delete merged branches

Fetches remote, finds deleted branches, and removes them locally.

Examples:
  git-prune                   # Clean up merged branches
HELP
        return 0
    }
    git fetch -p && git branch -vv | awk '/: gone]/{print $1}' | xargs -r git branch -D
}

git-largest() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: git-largest            Show largest files in git history

Lists top 20 largest blobs in repository history.

Output:
  Size | file path

Examples:
  git-largest                 # Show largest files
HELP
        return 0
    }
    git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | awk '/^blob/ {print $3, $4}' | sort -rn | head -20 | numfmt --field=1 --to=iec
}

# ─────────────────────────────────────────────────────────────────────────────
# FZF — integrated, safe bindings
# ─────────────────────────────────────────────────────────────────────────────
if _has fzf; then
    fzf-history() { local cmd=$(history | fzf --tac --no-sort --height 40% --reverse | sed 's/^[ ]*[0-9]*[ ]*//'); [[ -n $cmd ]] && { echo "$cmd"; eval "$cmd"; }; }
    fzf-kill() { local pid=$(ps aux | fzf --header="Kill process" --height 40% --reverse | awk '{print $2}'); [[ -n $pid ]] && kill -9 "$pid"; }
    fzf-cd() { local dir=$(find ~ -type d 2>/dev/null | fzf --preview 'ls -la {}' --height 60% --reverse); [[ -n $dir ]] && cd "$dir"; }
    fzf-git-branch() { git branch --all --format='%(refname:short)' | fzf --height 40% --reverse | xargs -r git checkout; }
    fzf-git-log() { git log --oneline --all | fzf --height 60% --reverse --preview 'git show --color=always {1}' | awk '{print $1}' | xargs -r git show; }
    fzf-ssh() { ssh-list | fzf --height 40% --reverse | awk '{print $1}' | xargs -r ssh; }
    fzf-env() { env | fzf --height 40% --reverse; }
    fzf-alias() { alias | fzf --height 40% --reverse; }

    # Key bindings (only in interactive shells)
    [[ $- == *i* ]] && {
        bind -x '"\C-r": fzf-history' 2>/dev/null
        bind -x '"\C-f": fzf-cd' 2>/dev/null
        bind -x '"\C-g": fzf-git-branch' 2>/dev/null
    }
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECRETS — age-encrypted ~/.secrets/
# ─────────────────────────────────────────────────────────────────────────────
_secrets_dir="$HOME/.secrets"
mkdir -p "$_secrets_dir" && chmod 700 "$_secrets_dir"

secret-set() {
    [[ $# -lt 2 ]] && { echo "secret-set <name> <value>"; return 1; }
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: secret-set <name> <value>

Store a secret value encrypted with AES256.

Arguments:
  name          Secret identifier
  value         Secret value to store

Storage:
  ~/.secrets/<name>.gpg

Environment:
  AGE_PASSPHRASE    Decryption passphrase (default: 'secret')

Examples:
  secret-set api-key "abc123"       # Store API key
  secret-set db-pass "mypassword"   # Store password
HELP
        return 0
    }
    _has gpg || { _die "gpg required"; return 1; }
    printf '%s' "$2" | gpg --symmetric --cipher AES256 --batch --yes --passphrase "${AGE_PASSPHRASE:-secret}" -o "$_secrets_dir/$1.gpg"
    _ok "Stored: $1"
}
secret-get() {
    [[ -z $1 ]] && { echo "secret-get <name>"; return 1; }
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: secret-get <name>

Retrieve and decrypt a stored secret.

Arguments:
  name          Secret identifier

Output:
  Decrypted secret value to stdout

Environment:
  AGE_PASSPHRASE    Decryption passphrase (default: 'secret')

Examples:
  secret-get api-key              # Retrieve API key
  secret-get db-pass              # Retrieve password
HELP
        return 0
    }
    gpg --decrypt --batch --yes --passphrase "${AGE_PASSPHRASE:-secret}" "$_secrets_dir/$1.gpg" 2>/dev/null || { _warn "Not found or wrong passphrase"; return 1; }
}
secret-list() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: secret-list

List all stored secrets.

Output:
  Names of all stored secrets

Examples:
  secret-list                     # List all secrets
  ls ~/.secrets                   # Same as secret-list
HELP
        return 0
    }
    for f in "$_secrets_dir"/*.gpg; do [[ -f $f ]] && basename "$f" .gpg; done
}
secret-edit() {
    [[ -z $1 ]] && { echo "secret-edit <name>"; return 1; }
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
Usage: secret-edit <name>

Edit a stored secret using your editor.

Arguments:
  name          Secret identifier

Editor:
  Uses $EDITOR (default: vim)

Examples:
  secret-edit api-key             # Edit API key
  secret-edit db-pass             # Edit password
HELP
        return 0
    }
    local tmp=$(mktemp)
    secret-get "$1" > "$tmp" 2>/dev/null || true
    ${EDITOR:-vim} "$tmp" && secret-set "$1" "$(cat $tmp)"
    rm -f "$tmp"
}

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP / SYNC — smart excludes, progress
# ─────────────────────────────────────────────────────────────────────────────
backup-projects() {
    local dest=${1:-"$HOME/backups/projects-$(date +%Y%m%d-%H%M).tar.zst"}
    mkdir -p "$(dirname "$dest")"
    _info "Backing up ~/projects → $dest"
    tar --zstd -cf "$dest" --exclude='node_modules' --exclude='__pycache__' --exclude='.git' --exclude='dist' --exclude='build' --exclude='target' --exclude='.next' --exclude='.cache' --exclude='*.egg-info' --exclude='.venv' --exclude='venv' --exclude='.env*' -C ~/projects . &
    _spin $! "Archiving"
    _ok "Backup: $dest ($(du -h "$dest" | cut -f1))"
}

sync-usb() { [[ -z $1 ]] && { echo "sync-usb <dest>"; return 1; }; _has rsync || { _die "rsync required"; return 1; }; rsync -avh --progress --delete --exclude='node_modules' --exclude='__pycache__' --exclude='.git' --exclude='*.log' --exclude='dist' --exclude='build' ~/projects/ "$1"/; }

sync-remote() { [[ $# -lt 2 ]] && { echo "sync-remote <host:path> <local>"; return 1; }; rsync -avh --progress --partial --delete --exclude='node_modules' --exclude='__pycache__' --exclude='.git' "$1" "$2"; }

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM INFO — dynamic, pretty
# ─────────────────────────────────────────────────────────────────────────────
sysinfo() {
    echo -e "${BOLD}${CYAN}══ System Info ══${NC}"
    echo -e "  Host:     $(hostname)  ($(uname -sr))"
    echo -e "  CPU:      $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)  ($(nproc) cores)"
    echo -e "  Load:     $(cut -d' ' -f1-3 /proc/loadavg)"
    echo -e "  Memory:   $(free -h | awk '/Mem:/ {print $3 " / " $2 " (" int($3/$2*100) "%)"}')"
    echo -e "  Disk:     $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    echo -e "  Uptime:   $(uptime -p)"
    echo -e "  Shell:    $SHELL ($BASH_VERSION)"
    for t in git node npm python3 docker kubectl terraform ansible age gpg; do
        _has "$t" && echo -e "  ${GREEN}✓${NC} $t" || echo -e "  ${DIM}✗${NC} $t"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# HELP — auto-generated from functions
# ─────────────────────────────────────────────────────────────────────────────
dynhelp() {
    echo -e "${BOLD}${CYAN}═══ Dynamic Core Commands ═══${NC}"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # ARCHIVE & FILE MANAGEMENT
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}📦 Archive & Files:${NC}"
    echo -e "    compress <path> [algo] [--fast|--best]     # Auto-detect format, smart excludes"
    echo -e "    extract <archive> [dest] [--strip N]       # Multi-format with progress"
    echo -e "    test-archive <archive>                     # Verify integrity"
    echo -e "    find-dupes <dir>                           # Find duplicate files"
    echo -e "    backup <src> [dest]                        # Timestamped backup"
    echo -e "    backup-projects [dest]                     # Backup ~/projects"
    echo -e "    sync-usb <dest>                            # rsync to USB with smart excludes"
    echo -e "    sync-remote <host:path> <local>            # Remote rsync"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # CRYPTOGRAPHY & SECURITY
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}🔐 Crypto & Secrets:${NC}"
    echo -e "    encrypt <path> [recipient] [--armor]       # age (recipient) or gpg (passphrase)"
    echo -e "    decrypt <file.age|file.gpg>                # Decrypt encrypted file"
    echo -e "    secret-set <name> <value>                  # Store secret (AES256)"
    echo -e "    secret-get <name>                          # Retrieve secret"
    echo -e "    secret-list                                # List stored secrets"
    echo -e "    secret-edit <name>                         # Edit secret"
    echo -e "    ssh-hardening                              # Audit SSH config & permissions"
    echo -e "    cert-check <cert.pem>                      # Check TLS certificate"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # SSH & TAILSCALE
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}🔗 SSH & Tailscale:${NC}"
    echo -e "    ssh-add-key [alias]                        # Interactive host setup wizard"
    echo -e "    ssh-list                                   # List configured hosts"
    echo -e "    ssh-test <alias>                           # Test connection"
    echo -e "    ssh-copy-id-auto <alias>                   # Deploy key to host"
    echo -e "    ts-up [args]                               # Start tailscaled + advertise routes"
    echo -e "    ts-ssh <host>                              # SSH via Tailscale"
    echo -e "    ts-funnel <port> [tcp|https]               # Expose port publicly"
    echo -e "    ts-serve <port> [path]                     # Serve locally via Tailscale"
    echo -e "    ts-status                                  # Pretty peer list"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # CLOUDFLARE
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}☁️ Cloudflare:${NC}"
    echo -e "    cf-dns-list <zone_id>                      # List DNS records"
    echo -e "    cf-dns-add <zone> <type> <name> <content>  # Add DNS record"
    echo -e "    cf-tunnel-create <name>                    # Create cloudflared tunnel"
    echo -e "    cf-tunnel-route <tunnel> <host> <svc>      # Route hostname to service"
    echo -e "    cf-tunnel-run <tunnel>                     # Run tunnel"
    echo -e "    cf-cache-purge <zone> [urls...]            # Purge cache"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # GIT VERSION CONTROL
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}📝 Git Tools:${NC}"
    echo -e "    git-root                                   # CD to repo root"
    echo -e "    git-recent [n]                             # Show recent branches"
    echo -e "    git-wip                                    # Quick WIP commit"
    echo -e "    git-unwip                                  # Undo last WIP commit"
    echo -e "    git-standup [days]                         # My commits across projects"
    echo -e "    git-prune                                  # Delete merged branches"
    echo -e "    git-largest                                # Largest files in history"
    echo -e "    git-stats                                  # Repo statistics"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # DOCKER CONTAINER MANAGEMENT
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}🐳 Docker:${NC}"
    echo -e "    docker-tui                                 # Full TUI (Textual)"
    echo -e "    dps                                        # Container list"
    echo -e "    dtop                                       # Live container stats"
    echo -e "    dlogs <container>                          # View logs"
    echo -e "    dshell <container>                         # Shell into container"
    echo -e "    dstart / dstop <container>                 # Start/stop"
    echo -e "    drm <container>                            # Remove container"
    echo -e "    dimages                                    # Image list"
    echo -e "    dvolumes                                   # Volume list"
    echo -e "    dnetworks                                  # Network list"
    echo -e "    dcompose <up|down|logs|ps|build>           # Compose operations"
    echo -e "    dprune                                     # Clean unused resources"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # DEVELOPMENT TOOLS
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}💻 Dev Tools:${NC}"
    echo -e "    proj-scan                                  # Scan for git repos"
    echo -e "    py-fmt                                     # Format Python (black/ruff)"
    echo -e "    py-lint                                    # Lint Python"
    echo -e "    npm-check                                  # Check npm deps"
    echo -e "    cargo-check                                # Check Rust project"
    echo -e "    go-check                                   # Check Go project"
    echo -e "    json-fmt <file>                            # Format JSON"
    echo -e "    json-lint <file>                           # Lint JSON"
    echo -e "    json-get <file> <path>                     # Extract JSON value"
    echo -e "    json-set <file> <path> <val>               # Set JSON value"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # UTILITIES
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}🛠️ Utilities:${NC}"
    echo -e "    calc <expression>                          # Calculator (bc/python)"
    echo -e "    cal                                      # Calendar"
    echo -e "    encode <text>                              # Base64/URL/HTML encoding"
    echo -e "    random <type>                              # UUID/password/dice"
    echo -e "    notes [search]                             # Quick markdown notes"
    echo -e "    todo                                       # Task management"
    echo -e "    bench                                      # System benchmarks"
    echo -e "    health                                     # System health check"
    echo -e "    pkg-audit                                  # Audit packages"
    echo -e "    edit-config                                # Edit ~/.bashrc, etc."
    echo -e "    dotfiles                                   # Manage dotfiles"
    echo -e "    theme                                      # Switch color schemes"
    echo -e "    keys                                       # View keybindings"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # SYSTEM MONITORING
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}📊 System Monitor:${NC}"
    echo -e "    sysinfo                                    # Full system overview"
    echo -e "    sysresources                               # Live CPU/memory/top"
    echo -e "    diskinfo                                   # Disk usage breakdown"
    echo -e "    myip                                       # Network info"
    echo -e "    psgrep <pattern>                           # Find processes"
    echo -e "    quickclean                                 # Clean journal/npm/pip"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # FZF KEYBINDINGS (if installed)
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}⌨️ FZF Shortcuts:${NC}"
    echo -e "    Ctrl-R      History search"
    echo -e "    Ctrl-F      Directory jump"
    echo -e "    Ctrl-G      Git branch checkout"
    echo -e "    fzf-kill    Kill process picker"
    echo -e "    fzf-ssh     SSH host picker"
    echo -e "    fzf-git-log Git log browser"
    echo ""
    
    # ────────────────────────────────────────────────────────────────────────
    # QUICK REFERENCE
    # ────────────────────────────────────────────────────────────────────────
    echo -e "  ${BOLD}💡 Tips:${NC}"
    echo -e "    • Type ${CYAN}dm${NC} for interactive menu"
    echo -e "    • Type ${CYAN}mvhelp${NC} for MV Maestro help"
    echo -e "    • Set ${CYAN}CF_API_TOKEN${NC} for Cloudflare commands"
    echo -e "    • Set ${CYAN}AGE_PASSPHRASE${NC} for GPG encryption"
}

# Init message intentionally omitted — consolidated into a single message
# printed once all modules finish loading (see dynamic_menu.sh).