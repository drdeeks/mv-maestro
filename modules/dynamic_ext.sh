#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# SQLITE DATABASE VIEWER
# ─────────────────────────────────────────────────────────────────────────────

# sqlite-view <db_file> [table] — browse SQLite database with fzf
sqlite-view() {
    [[ $# -eq 0 ]] && { echo "Usage: sqlite-view <db_file> [table]"; return 1; }
    local db="$1" table="$2"
    [[ -f $db ]] || { _die "Database not found: $db"; return 1; }
    _has sqlite3 || { _die "sqlite3 not installed"; return 1; }

    if [[ -z $table ]]; then
        table=$(sqlite3 "$db" ".tables" | tr ' ' '\n' | fzf --prompt="Select table> " --height 50% --reverse) || return 1
    fi

    local cols=$(sqlite3 "$db" "PRAGMA table_info($table)" | cut -d'|' -f2 | tr '\n' ',' | sed 's/,$//')

    sqlite3 -header -column "$db" "SELECT * FROM $table" | fzf \
        --header "Table: $table | Columns: $cols" \
        --preview "sqlite3 -header -column $db \"SELECT * FROM $table WHERE rowid = {1}\"" \
        --preview-window "down:50%" \
        --bind "enter:execute(echo {})" \
        --bind "ctrl-e:execute(sqlite3 $db \".schema $table\" | less)" \
        --bind "ctrl-c:cancel"
}

# sqlite-query <db_file> <sql> — run custom query with pretty output
sqlite-query() {
    [[ $# -lt 2 ]] && { echo "Usage: sqlite-query <db_file> <sql>"; return 1; }
    local db="$1"; shift
    local sql="$*"
    [[ -f $db ]] || { _die "Database not found: $db"; return 1; }
    _has sqlite3 || { _die "sqlite3 not installed"; return 1; }
    sqlite3 -header -column "$db" "$sql" | fzf --preview "echo {} | column -t -s'|'" --preview-window "down:30%"
}

# sqlite-edit <db_file> <table> <rowid> — edit a row interactively
sqlite-edit() {
    [[ $# -lt 3 ]] && { echo "Usage: sqlite-edit <db_file> <table> <rowid>"; return 1; }
    local db="$1" table="$2" rowid="$3"
    [[ -f $db ]] || { _die "Database not found: $db"; return 1; }
    _has sqlite3 || { _die "sqlite3 not installed"; return 1; }

    local cols=$(sqlite3 "$db" "PRAGMA table_info($table)" | cut -d'|' -f2 | tr '\n' ' ')
    local pk=$(sqlite3 "$db" "PRAGMA table_info($table)" | awk -F'|' '$6==1 {print $2}')

    local current=$(sqlite3 "$db" "SELECT * FROM $table WHERE rowid = $rowid")
    IFS='|' read -ra vals <<< "$current"

    local new_vals=()
    local idx=0
    for col in $cols; do
        local current_val="${vals[$idx]}"
        read -rp "$col [$current_val]: " new_val
        new_vals+=("${new_val:-$current_val}")
        ((idx++))
    done

    local set_clause=""
    local idx=0
    for col in $cols; do
        [[ $col == "$pk" ]] && { idx=$((idx+1)); continue; }
        set_clause+="$col = '${new_vals[$idx]}', "
        ((idx++))
    done
    set_clause="${set_clause%, }"

    sqlite3 "$db" "UPDATE $table SET $set_clause WHERE rowid = $rowid"
    _ok "Updated row $rowid in $table"
}

# ─────────────────────────────────────────────────────────────────────────────
# SOCKET CLI
# ─────────────────────────────────────────────────────────────────────────────

# sock-connect <host> <port> — connect to TCP socket with readline
sock-connect() {
    [[ $# -lt 2 ]] && { echo "Usage: sock-connect <host> <port>"; return 1; }
    local host="$1" port="$2"
    _has nc || _has ncat || { _die "nc or ncat required"; return 1; }
    # Validate inputs
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || { _die "Invalid port: $port"; return 1; }
    [[ "$host" =~ ^[a-zA-Z0-9.:_-]+$ ]] || { _die "Invalid host: $host"; return 1; }
    
    if _has ncat; then
        ncat -C "$host" "$port"
    else
        if _has socat; then
            socat - "TCP:$host:$port,crnl"
        else
            echo "Warning: using nc without CRLF support" >&2
            nc "$host" "$port"
        fi
    fi
}

# sock-listen <port> [bind_addr] — start TCP listener (echoes back)
sock-listen() {
    [[ $# -eq 0 ]] && { echo "Usage: sock-listen <port> [bind_addr]"; return 1; }
    _has nc || { _die "nc required"; return 1; }
    local port="$1" bind_addr="${2:-127.0.0.1}"
    # Validate port
    [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 )) || { _die "Invalid port: $1"; return 1; }
    # Validate bind_addr (basic IP/hostname check)
    [[ "$2" =~ ^[a-zA-Z0-9.:_-]+$ ]] || { _die "Invalid bind address: $2"; return 1; }
    
    echo "Listening on ${bind_addr}:${port} (Ctrl+C to stop)..."
    # Use nc without -c flag (no shell execution) - nc echoes by default
    # Use timeout to prevent indefinite hangs, socat if available for better handling
    if _has socat; then
        socat TCP-LISTEN:"$port",bind="$bind_addr",reuseaddr,fork EXEC:cat
    else
        # nc without -c flag - no shell execution
        while true; do
            nc -l -s "$bind_addr" -p "$1"
        done
    fi
}

# sock-send <host> <port> <file> — send file over TCP
sock-send() {
    [[ $# -lt 3 ]] && { echo "Usage: sock-send <host> <port> <file>"; return 1; }
    local host="$1" port="$2" file="$3"
    [[ -f $file ]] || { _die "File not found: $file"; return 1; }
    _has nc || _has ncat || { _die "nc or ncat required"; return 1; }
    # Validate inputs
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || { _die "Invalid port: $port"; return 1; }
    [[ "$host" =~ ^[a-zA-Z0-9.:_-]+$ ]] || { _die "Invalid host: $host"; return 1; }
    
    # Use ncat if available (supports -C for CRLF), fallback to nc
    if _has ncat; then
        cat "$file" | ncat -C "$host" "$port"
    else
        cat "$file" | nc -q 1 "$host" "$port"
    fi
}

# sock-recv <port> <output_file> [bind_addr] — receive file over TCP
sock-recv() {
    [[ $# -lt 2 ]] && { echo "Usage: sock-recv <port> <output_file> [bind_addr]"; return 1; }
    local port="$1" file="$2" bind_addr="${3:-127.0.0.1}"
    _has nc || { _die "nc required"; return 1; }
    # Validate inputs
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || { _die "Invalid port: $port"; return 1; }
    [[ "$bind_addr" =~ ^[a-zA-Z0-9.:_-]+$ ]] || { _die "Invalid bind address: $bind_addr"; return 1; }
    
    echo "Receiving on ${bind_addr}:${port}..."
    if _has socat; then
        socat TCP-LISTEN:"$port",bind="$bind_addr",reuseaddr FILE:"$file",creat,trunc
    else
        nc -l -s "$bind_addr" -p "$port" > "$file"
    fi
    _ok "Received: $file ($(du -h "$file" | cut -f1))"
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND HISTORY BROWSER (SCROLLABLE)
# ─────────────────────────────────────────────────────────────────────────────

# hist-browse — browse command history with fzf (scrollable, searchable)
hist-browse() {
    _has fzf || { _die "fzf required"; return 1; }
    
    local hist_file="${HISTFILE:-$HOME/.bash_history}"
    [[ -f $hist_file ]] || { _die "History file not found: $hist_file"; return 1; }
    
    tac "$hist_file" | awk '!seen[$0]++' | fzf \
        --height 90% \
        --reverse \
        --prompt "History> " \
        --preview "echo {} | bat --color=always -l bash 2>/dev/null || echo {}" \
        --preview-window "right:60%" \
        --bind "enter:execute-silent(echo {} | xclip -selection clipboard 2>/dev/null || echo {} | pbcopy 2>/dev/null)+abort" \
        --bind "ctrl-y:execute-silent(echo {} | xclip -selection clipboard 2>/dev/null || echo {} | pbcopy 2>/dev/null)+abort" \
        --bind "ctrl-e:execute($EDITOR <<< {})+accept" \
        --bind "ctrl-r:toggle-sort" \
        --header "Enter: copy to clipboard | Ctrl-E: edit in \$EDITOR | Ctrl-R: toggle sort"
}

# hist-search <pattern> — search history for pattern
hist-search() {
    [[ $# -eq 0 ]] && { echo "Usage: hist-search <pattern>"; return 1; }
    local hist_file="${HISTFILE:-$HOME/.bash_history}"
    grep -i "$*" "$hist_file" | tac | awk '!seen[$0]++' | fzf \
        --height 90% \
        --reverse \
        --prompt "History> " \
        --bind "enter:execute-silent(echo {} | xclip -selection clipboard 2>/dev/null || echo {} | pbcopy 2>/dev/null)+abort"
}

# hist-replay — replay last N commands step by step
hist-replay() {
    local n=${1:-10}
    local hist_file="${HISTFILE:-$HOME/.bash_history}"
    tail -n "$n" "$hist_file" | nl | fzf \
        --height 50% \
        --reverse \
        --prompt "Replay> " \
        --preview "echo {} | cut -f2- | bat --color=always -l bash 2>/dev/null || echo {}" \
        --bind "enter:execute-silent(echo {} | cut -f2- | xclip -selection clipboard 2>/dev/null || echo {} | cut -f2- | pbcopy 2>/dev/null)+abort"
}

# Init message intentionally omitted — consolidated into a single message
# printed once all modules finish loading (see dynamic_menu.sh).
