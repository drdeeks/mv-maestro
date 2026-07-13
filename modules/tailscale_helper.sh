#!/usr/bin/env bash
# =============================================================================
# Tailscale Helper - Device Management & Closed Network Setup
# Usage: tailscale-helper [command]
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

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

print_header() {
    echo -e "\n${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Tailscale Helper                                      ║${NC}"
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

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
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
# CORE TAILSCALE COMMANDS
# ─────────────────────────────────────────────────────────────────────────────

check_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        echo -e "${RED}✗ Tailscale not installed${NC}"
        echo "Install from: https://tailscale.com/download"
        return 1
    fi
    
    if ! systemctl is-active --quiet tailscaled 2>/dev/null && \
       ! pgrep -x tailscaled >/dev/null 2>&1; then
        print_warning "Tailscale daemon not running"
        echo "Start with: sudo systemctl start tailscaled"
        return 1
    fi
    
    return 0
}

status() {
    print_header
    echo -e "${CYAN}Tailscale Status:${NC}"
    tailscale status 2>/dev/null || echo "Failed to get status"
    echo ""
    echo -e "${CYAN}Tailscale IP:${NC}"
    tailscale ip 2>/dev/null || echo "Not connected"
}

login_interactive() {
    print_header
    print_step 1 "Authentication"
    
    echo "You will be redirected to a browser for authentication."
    echo "If running headless, use the key provided below."
    echo ""
    
    if yes_no_question "Login now?"; then
        tailscale login
        print_success "Login complete!"
        tailscale status | head -10
    fi
}

logout() {
    if yes_no_question "Logout from Tailscale?"; then
        tailscale logout
        print_success "Logged out"
    fi
}

up() {
    if check_tailscale; then
        tailscale up "$@"
        print_success "Tailscale brought up"
        status
    fi
}

down() {
    if yes_no_question "Bring down Tailscale?"; then
        tailscale down
        print_success "Tailscale brought down"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# DEVICE MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

list_devices() {
    print_header
    echo -e "${CYAN}Connected Tailscale Devices:${NC}\n"
    
    if tailscale status --json 2>/dev/null | python3 -c "
import sys
import json

data = json.load(sys.stdin)
devices = data.get('Self', {})
other_devices = data.get('OtherDevices', [])

print(f\"{'Name':<25} {'IP':<18} {'Online':<10} {'OS':<10}\")
print('-' * 63)

# Self device
self_name = devices.get('Name', 'self')
self_ip = devices.get('Addresses', [''])[0].split('/')[0]
print(f\"{self_name:<25} {self_ip:<18} {'yes':<10} {'-':<10}\")

# Other devices
for dev in other_devices:
    name = dev.get('Name', 'unknown')
    ip = dev.get('Addresses', [''])[0].split('/')[0] if dev.get('Addresses') else '-'
    online = 'yes' if dev.get('Online', False) else 'no'
    os = dev.get('OS', '-').lower()[:10]
    print(f\"{name:<25} {ip:<18} {online:<10} {os:<10}\")
" 2>/dev/null; then
        :
    else
        # Fallback to text output
        tailscale status 2>/dev/null | grep -v "^#" | head -20
    fi
}

get_device_ip() {
    local device_name="${1:-}"
    
    if [[ -z "$device_name" ]]; then
        echo "Usage: ts-ip <device-name>"
        echo "Available devices:"
        list_devices
        return 1
    fi
    
    local ip=$(tailscale status --json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for dev in data.get('OtherDevices', []):
    if dev.get('Name', '').startswith('$device_name'):
        print(dev.get('Addresses', [''])[0].split('/')[0])
        break
" 2>/dev/null)
    
    if [[ -n "$ip" ]]; then
        echo "$ip"
    else
        echo -e "${RED}✗ Device not found: $device_name${NC}"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOSED NETWORK / ACL SETUP
# ─────────────────────────────────────────────────────────────────────────────

setup_closed_network() {
    print_header
    
    print_step 1 "Network Configuration"
    local subnet=$(ask_question "Subnet range (e.g., 10.0.0.0/24)" "100.64.0.0/10")
    
    print_step 2 "Access Control"
    echo "Configure which devices can communicate with each other."
    echo "By default, all devices in your tailnet can communicate."
    echo ""
    
    if yes_no_question "Set up restricted access controls?"; then
        echo "You'll need to configure ACLs in the Tailscale Admin Panel:"
        echo "  https://login.tailscale.com/admin/acls"
        echo ""
        echo "Example ACL policy (JSON):"
        cat << 'ACLEOF'
{
    "groups": {
        "group:developers": ["user1@example.com", "user2@example.com"],
        "group:servers": ["server1", "server2"]
    },
    "hosts": {
        "web-server": "100.100.100.100",
        "db-server": "100.100.100.101"
    },
    "acls": [
        {"action": "accept", "src": ["group:developers"], "dst": ["group:servers:*"]},
        {"action": "accept", "src": ["group:servers"], "dst": ["group:servers:22"]}
    ],
    "tagOwners": {
        "tag:production": ["admin@example.com"]
    }
}
ACLEOF
        echo ""
        print_info "After setting ACLs, run: tailscale set --acl-file=acl-policy.json"
    else
        print_info "Using default open access within tailnet"
    fi
    
    print_step 3 "Enable Features"
    
    local exit_node="n"
    local subnet_router="n"
    local app_connector="n"
    
    if yes_no_question "Enable as Exit Node (route all traffic through this device)?"; then
        exit_node="y"
    fi
    
    if yes_no_question "Enable Subnet Router (advertise local network)?"; then
        subnet_router="y"
        local subnet_range=$(ask_question "Subnet to advertise (e.g., 192.168.1.0/24)" "")
    fi
    
    # Apply configuration
    local flags=""
    [[ "$exit_node" == "y" ]] && flags+=" --exit-node=all"
    [[ "$subnet_router" == "y" ]] && flags+=" --advertise-routes=${subnet_range:-}"
    
    if [[ -n "$flags" ]]; then
        tailscale up $flags 2>/dev/null
        print_success "Configuration applied"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# QUICK CONNECT HELPERS
# ─────────────────────────────────────────────────────────────────────────────

ssh_to_device() {
    local device="${1:-}"
    
    if [[ -z "$device" ]]; then
        echo "Usage: ts-ssh <device-name>"
        list_devices
        return 1
    fi
    
    local ip=$(get_device_ip "$device")
    if [[ $? -eq 0 ]]; then
        ssh "$ip"
    fi
}

scp_to_device() {
    local device="${1:-}"
    local file="${2:-}"
    local dest="${3:-}"
    
    if [[ -z "$device" || -z "$file" ]]; then
        echo "Usage: ts-scp <device> <file> [destination]"
        return 1
    fi
    
    local ip=$(get_device_ip "$device")
    if [[ $? -eq 0 ]]; then
        scp "$file" "$ip:$dest"
    fi
}

ping_device() {
    local device="${1:-}"
    
    if [[ -z "$device" ]]; then
        echo "Usage: ts-ping <device-name>"
        return 1
    fi
    
    local ip=$(get_device_ip "$device")
    if [[ $? -eq 0 ]]; then
        ping -c 4 "$ip"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MAGIC DNS / HOSTNAME RESOLUTION
# ─────────────────────────────────────────────────────────────────────────────

enable_magic_dns() {
    print_header
    
    if yes_no_question "Enable MagicDNS?"; then
        tailscale up --accept-dns=true
        print_success "MagicDNS enabled"
        echo ""
        echo "You can now reach devices by hostname instead of IP:"
        echo "  ssh mylaptop"
        echo "  ping myserver"
        echo ""
        echo "View DNS settings: tailscale status --dns"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# TRoubleshooting
# ─────────────────────────────────────────────────────────────────────────────

diagnose() {
    print_header
    echo -e "${CYAN}Running Tailscale Diagnostics...${NC}\n"
    
    echo "1. Daemon Status:"
    if pgrep -x tailscaled >/dev/null 2>&1; then
        print_success "tailscaled is running"
    else
        print_warning "tailscaled is NOT running"
        echo "  Start with: sudo systemctl start tailscaled"
    fi
    echo ""
    
    echo "2. Login Status:"
    if tailscale status --json 2>/dev/null | grep -q '"Authenticated":true'; then
        print_success "Authenticated to Tailscale"
    else
        print_warning "NOT authenticated"
        echo "  Login with: tailscale login"
    fi
    echo ""
    
    echo "3. Connectivity Test:"
    local test_host="100.100.100.100"  # Tailscale's test host
    if ping -c 2 -W 2 "$test_host" >/dev/null 2>&1; then
        print_success "Can reach Tailscale network"
    else
        print_warning "Cannot reach Tailscale network"
    fi
    echo ""
    
    echo "4. Recent Logs:"
    tailscale bugreport 2>/dev/null | tail -5 || echo "  Unable to fetch logs"
}

# ─────────────────────────────────────────────────────────────────────────────
# HELP / USAGE
# ─────────────────────────────────────────────────────────────────────────────

show_help() {
    cat << 'HELPEOF'

╔═══════════════════════════════════════════════════════════╗
║        Tailscale Helper - Quick Reference                 ║
╚═══════════════════════════════════════════════════════════╝

STATUS & CONNECTION:
  ts-status                    # Show connection status
  ts-login                     # Interactive login
  ts-logout                    # Logout
  ts-up                        # Bring interface up
  ts-down                      # Bring interface down
  ts-diagnose                  # Run diagnostics

DEVICE MANAGEMENT:
  ts-devices                   # List all connected devices
  ts-ip <device>               # Get IP of specific device
  ts-ssh <device>              # SSH to device via Tailscale
  ts-scp <device> <file>       # Copy file to device
  ts-ping <device>             # Ping device

NETWORK CONFIGURATION:
  ts-closed-network            # Setup closed network with ACLs
  ts-magic-dns                 # Enable MagicDNS (hostname resolution)

ADVANCED:
  tailscale status             # Full status (raw)
  tailscale ip                 # Show this machine's Tailscale IP
  tailscale whois <IP>         # Find device by IP
  tailscale set --advertise-ranges=<CIDR>  # Advertise subnet

CONVENIENCE ALIASES (add to ~/.bash_aliases_usb):
  alias ts='tailscale'
  alias ts-ssh='ssh'           # Use after getting IP with ts-ip
  alias ts-scp='scp'           # Use after getting IP with ts-ip

SECURITY BEST PRACTICES:
  • Use ACLs to restrict device-to-device communication
  • Enable MFA on Tailscale account
  • Use tags for production vs development devices
  • Regular audit of connected devices
  • Keep tailscale package updated

ACL POLICY EXAMPLE:
  See ts-closed-network for example ACL JSON

TROUBLESHOOTING:
  ts-diagnose                  # Automated diagnostics
  tailscale bugreport          # Generate support ticket
  tailscale debug --prefs      # View current preferences

HELPEOF
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT (only runs if executed directly, not when sourced)
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        status|st)
            status
            ;;
        login|auth)
            login_interactive
            ;;
        logout|logoff)
            logout
            ;;
        up|start)
            up "${@:2}"
            ;;
        down|stop)
            down
            ;;
        devices|list|ls)
            list_devices
            ;;
        ip|get-ip)
            get_device_ip "${2:-}"
            ;;
        ssh|connect)
            ssh_to_device "${2:-}"
            ;;
        scp|copy)
            scp_to_device "${2:-}" "${3:-}" "${4:-}"
            ;;
        ping)
            ping_device "${2:-}"
            ;;
        closed-network|acl|network)
            setup_closed_network
            ;;
        magic-dns|dns)
            enable_magic_dns
            ;;
        diagnose|diag|debug)
            diagnose
            ;;
        help|--help|-h|"")
            show_help
            ;;
        *)
            # Pass unknown commands to tailscale directly
            tailscale "$@"
            ;;
    esac
fi
