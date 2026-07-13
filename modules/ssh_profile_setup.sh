#!/usr/bin/env bash
# =============================================================================
# SSH Profile Setup Wizard
# Interactive guided setup for SSH host profiles with optional automation
# Source from: ~/.bashrc or ~/.bash_profile_enhanced/bash_enhanced.sh
# Usage after sourcing: ssh-profile-setup [hostname] [interactive|auto]
# =============================================================================
# set -euo pipefail  # Disabled for interactive sourcing
set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SSH_DIR="$HOME/.ssh"
SSH_CONFIG_D="$SSH_DIR/config.d"
SSH_ALIASES_FILE="$HOME/.ssh_aliases"

# Initialize directories
mkdir -p "$SSH_CONFIG_D" 2>/dev/null || true
chmod 700 "$SSH_DIR" "$SSH_CONFIG_D" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

print_header() {
    echo -e "\n${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     SSH Profile Setup Wizard                              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}\n"
}

print_step() {
    echo -e "${BLUE}[Step $1]${NC} $2"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

ask_question() {
    local prompt="$1"
    local default="${2:-}"
    local response
    
    if [[ -n "$default" ]]; then
        read -rp "$prompt [$default]: " response
        echo "${response:-$default}"
    else
        read -rp "$prompt: " response
        echo "$response"
    fi
}

yes_no_question() {
    local prompt="$1"
    local default="${2:-y}"
    
    read -rp "$prompt [Y/n]: " response
    case "${response:-$default}" in
        [Yy]* | "") return 0 ;;
        *) return 1 ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# CORE SETUP FUNCTION
# ─────────────────────────────────────────────────────────────────────────────

setup_ssh_profile() {
    local hostname="${1:-}"
    local alias_name="${2:-}"
    local ip_address="${3:-}"
    local username="${4:-}"
    local identity_file="${5:-}"
    
    # Interactive mode if not all params provided
    if [[ -z "$hostname" ]]; then
        print_header
        
        print_step 1 "Host Information"
        alias_name=$(ask_question "Enter an alias name (e.g., 'webserver', 'prod-db')" "")
        ip_address=$(ask_question "Enter IP address or domain" "")
        username=$(ask_question "Enter username" "ubuntu")
        
        print_step 2 "SSH Key Configuration"
        identity_file=$(ask_question "Identity file path" "~/.ssh/id_ed25519")
        
        # Expand ~ to full path
        identity_file="${identity_file/#\~/$HOME}"
    fi
    
    # Validate required fields
    if [[ -z "$alias_name" || -z "$ip_address" || -z "$username" ]]; then
        echo -e "${RED}✗ Error: All fields are required${NC}"
        return 1
    fi
    
    # Create config file
    local config_file="$SSH_CONFIG_D/${alias_name}.conf"
    
    cat > "$config_file" << EOF
# SSH Profile: $alias_name
# Created: $(date '+%Y-%m-%d %H:%M:%S')
Host $alias_name
    HostName $ip_address
    User $username
    IdentityFile $identity_file
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ForwardAgent no
    ForwardX11 no
EOF
    
    chmod 600 "$config_file"
    
    print_success "Created SSH config: $config_file"
    
    # Test connection
    if yes_no_question "Test SSH connection to $alias_name?"; then
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "$alias_name" true 2>/dev/null; then
            print_success "Connection successful!"
            
            # Add to known_hosts
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes "$alias_name" exit 2>/dev/null || true
        else
            echo -e "${YELLOW}⚠ Connection test failed. Check network/firewall settings.${NC}"
        fi
    fi
    
    # Offer to create convenience aliases
    if yes_no_question "Create convenience aliases for this host?"; then
        create_ssh_aliases "$alias_name" "$ip_address"
    fi
    
    # Offer to copy SSH key
    if yes_no_question "Copy SSH public key to remote host (for passwordless login)?"; then
        if [[ -f "${identity_file}.pub" ]]; then
            ssh-copy-id -i "${identity_file}.pub" "$username@$ip_address" 2>&1 || \
                echo -e "${YELLOW}⚠ ssh-copy-id failed. Manual setup may be required.${NC}"
        else
            echo -e "${YELLOW}⚠ Public key not found at ${identity_file}.pub${NC}"
        fi
    fi
    
    echo ""
    print_info "Usage:"
    echo "  ssh $alias_name              # Connect to host"
    echo "  scp file.txt $alias_name:/tmp/   # Copy file to host"
    echo "  rsync -av ./ $alias_name:/var/www/ # Sync directory"
    echo "  sftp $alias_name             # Open SFTP session"
    
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# CONVENIENCE ALIAS CREATION
# ─────────────────────────────────────────────────────────────────────────────

create_ssh_aliases() {
    local alias_name="$1"
    local ip_address="$2"
    
    # Append to .ssh_aliases
    cat >> "$SSH_ALIASES_FILE" << EOF

# Aliases for $alias_name ($(date '+%Y-%m-%d'))
alias ssh-$alias_name='ssh $alias_name'
alias scp-to-$alias_name='scp -r'
alias scp-from-$alias_name='scp -r $alias_name:'
alias rsync-to-$alias_name='rsync -av --progress'
alias rsync-from-$alias_name='rsync -av --progress $alias_name:'
alias sftp-$alias_name='sftp $alias_name'
alias ping-$alias_name='ping -c 4 $ip_address'
EOF
    
    # Source it if already loaded
    if [[ -n "${BASH_VERSION:-}" ]]; then
        source "$SSH_ALIASES_FILE" 2>/dev/null || true
    fi
    
    print_success "Created aliases in $SSH_ALIASES_FILE"
    print_info "Run 'source $SSH_ALIASES_FILE' or restart shell to use them"
}

# ─────────────────────────────────────────────────────────────────────────────
# BATCH SETUP FOR MULTIPLE HOSTS
# ─────────────────────────────────────────────────────────────────────────────

batch_setup_from_inventory() {
    local inventory_file="${1:-}"
    
    if [[ -z "$inventory_file" ]]; then
        echo "Usage: batch-ssh-setup <inventory-file>"
        echo "Inventory file format (one per line):"
        echo "  alias_name|ip_address|username"
        echo ""
        echo "Example:"
        echo "  web1|192.168.1.10|ubuntu"
        echo "  db1|192.168.1.20|postgres"
        return 1
    fi
    
    if [[ ! -f "$inventory_file" ]]; then
        echo -e "${RED}✗ Inventory file not found: $inventory_file${NC}"
        return 1
    fi
    
    local count=0
    while IFS='|' read -r alias_name ip_address username; do
        # Skip comments and empty lines
        [[ "$alias_name" =~ ^#.*$ || -z "$alias_name" ]] && continue
        
        echo -e "${CYAN}Setting up $alias_name ($ip_address)...${NC}"
        setup_ssh_profile "$alias_name" "" "$ip_address" "${username:-root}" ""
        count=$((count + 1))
    done < "$inventory_file"
    
    print_success "Set up $count hosts"
}

# ─────────────────────────────────────────────────────────────────────────────
# LIST ALL CONFIGURED HOSTS
# ─────────────────────────────────────────────────────────────────────────────

list_ssh_profiles() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Configured SSH Profiles                               ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}\n"
    
    if [[ ! -d "$SSH_CONFIG_D" ]]; then
        echo "No SSH profiles configured."
        return 0
    fi
    
    local count=0
    for config_file in "$SSH_CONFIG_D"/*.conf; do
        [[ -f "$config_file" ]] || continue
        
        local alias_name=$(basename "$config_file" .conf)
        local hostname=$(grep "^    HostName" "$config_file" | awk '{print $2}')
        local user=$(grep "^    User" "$config_file" | awk '{print $2}')
        
        echo -e "${GREEN}●${NC} $alias_name"
        echo "  Host: $hostname"
        echo "  User: $user"
        echo "  Config: $config_file"
        
        # Test connectivity
        if ssh -o ConnectTimeout=2 -o BatchMode=yes "$alias_name" true 2>/dev/null; then
            echo -e "  Status: ${GREEN}✓ Online${NC}"
        else
            echo -e "  Status: ${YELLOW}✗ Offline/Unreachable${NC}"
        fi
        echo ""
        
        count=$((count + 1))
    done
    
    if [[ $count -eq 0 ]]; then
        echo "No SSH profiles found in $SSH_CONFIG_D"
    else
        echo -e "${BLUE}Total: $count profile(s)${NC}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# REMOVE SSH PROFILE
# ─────────────────────────────────────────────────────────────────────────────

remove_ssh_profile() {
    local alias_name="${1:-}"
    
    if [[ -z "$alias_name" ]]; then
        echo "Usage: ssh-profile-remove <alias-name>"
        return 1
    fi
    
    local config_file="$SSH_CONFIG_D/${alias_name}.conf"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}✗ Profile not found: $alias_name${NC}"
        return 1
    fi
    
    if yes_no_question "Remove SSH profile '$alias_name'?"; then
        rm -f "$config_file"
        print_success "Removed profile: $alias_name"
        
        # Remove from known_hosts
        ssh-keygen -R "$alias_name" 2>/dev/null || true
        
        # Remove aliases if they exist
        if [[ -f "$SSH_ALIASES_FILE" ]]; then
            sed -i "/#$alias_name/,/^$/d" "$SSH_ALIASES_FILE" 2>/dev/null || true
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# QUICK HELP / USAGE
# ─────────────────────────────────────────────────────────────────────────────

show_ssh_help() {
    cat << 'HELPEOF'

╔═══════════════════════════════════════════════════════════╗
║          SSH Profile Setup - Quick Reference              ║
╚═══════════════════════════════════════════════════════════╝

INTERACTIVE SETUP:
  ssh-profile-setup                    # Start wizard
  ssh-profile-setup myserver           # Pre-fill alias name

MANUAL PARAMETERS:
  ssh-profile-setup <alias> <ip> <user> <keyfile>

BATCH SETUP FROM INVENTORY:
  ssh-batch-setup <inventory-file>
  
  Inventory format: alias|ip|username
  Example:
    web1|192.168.1.10|ubuntu
    db1|192.168.1.20|postgres

LIST PROFILES:
  ssh-profiles                         # List all configured hosts
  ssh-profile-check <alias>            # Test specific host

REMOVE PROFILE:
  ssh-profile-remove <alias>

CREATED CONVENIENCE COMMANDS:
  ssh <alias>                          # Connect to host
  scp file.txt <alias>:/path/          # Copy file to host
  scp <alias>:/path/file.txt .         # Copy file from host
  rsync -av ./ <alias>:/path/          # Sync to host
  rsync -av <alias>:/path/ ./          # Sync from host
  sftp <alias>                         # SFTP session
  ping <alias>                         # Test connectivity

OPTIONAL FEATURES DURING SETUP:
  • Test SSH connection immediately
  • Auto-create convenience aliases (ssh-X, scp-to-X, etc.)
  • Copy SSH public key for passwordless login
  • Add host to known_hosts automatically

CONFIG LOCATION:
  ~/.ssh/config.d/<alias>.conf

ALIASES FILE:
   ~/.ssh_aliases (run 'source ~/.ssh_aliases' to load)

HELPEOF
}

# User-friendly command aliases
alias ssh-profile-setup='setup_ssh_profile'
alias ssh-profiles='list_ssh_profiles'
alias ssh-profile-remove='remove_ssh_profile'
alias ssh-batch-setup='batch_setup_from_inventory'

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT (only runs if executed directly, not when sourced)
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        setup|add|new)
            setup_ssh_profile "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
            ;;
        list|ls)
            list_ssh_profiles
            ;;
        remove|del|rm)
            remove_ssh_profile "${2:-}"
            ;;
        batch|import)
            batch_setup_from_inventory "${2:-}"
            ;;
        check|test)
            if [[ -n "${2:-}" ]]; then
                ssh -v "${2:-}" 2>&1 | head -20
            else
                list_ssh_profiles
            fi
            ;;
        help|--help|-h|"")
            show_ssh_help
            ;;
        *)
            # Assume it's a hostname/alias and start interactive setup
            setup_ssh_profile "$1"
            ;;
    esac
fi
