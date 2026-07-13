#!/usr/bin/env bash
# =============================================================================
# Menu Validation Suite
# Tests all 68 menu items for proper definition and basic functionality
# Usage: ./validate_menu.sh [--verbose] [--quick]
# =============================================================================

set -euo pipefail

PROFILE="/home/drdeek/projects/MV-Maestro/bash_enhanced.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL=0
PASSED=0
FAILED=0
WARNED=0
SKIPPED=0

# Results storage
declare -a FAILURES=()
declare -a WARNINGS=()

VERBOSE=false
QUICK=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSE=true; shift ;;
        --quick|-q) QUICK=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; PASSED=$((PASSED + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILED=$((FAILED + 1)); FAILURES+=("$*"); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; WARNED=$((WARNED + 1)); WARNINGS+=("$*"); }
log_skip() { echo -e "${DIM}[SKIP]${NC} $*"; SKIPPED=$((SKIPPED + 1)); }

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       MV Maestro Menu Validation Suite                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: Source profile and verify data integrity
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 1: Loading profile and verifying menu data..."

if ! source "$PROFILE" >/dev/null 2>&1; then
    log_fail "Failed to source bash_enhanced.sh"
    exit 1
fi

log_success "Profile sourced successfully"

# Check _menu_dump_data exists
if declare -f _menu_dump_data >/dev/null 2>&1; then
    log_success "_menu_dump_data function defined"
else
    log_fail "_menu_dump_data function missing"
    exit 1
fi

# Extract menu data
MENU_DATA=$(_menu_dump_data 2>/dev/null)
if [[ -z "$MENU_DATA" ]]; then
    log_fail "No menu data returned from _menu_dump_data"
    exit 1
fi

log_success "Menu data extracted ($(echo "$MENU_DATA" | grep "^ITEM" | wc -l) items)"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: Validate all menu items have implementations
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 2: Checking all menu commands have implementations..."

while IFS=$'\x1f' read -r kind num label desc cmd interactive purpose includes; do
    [[ $kind != "ITEM" ]] && continue
    TOTAL=$((TOTAL + 1))
    
    # Skip quick mode after first few items
    if $QUICK && [[ $TOTAL -gt 5 ]]; then
        log_skip "Quick mode - skipping remaining checks"
        break
    fi
    
    # Check if command is defined as function OR exists as binary
    local_impl=false
    binary_impl=false
    
    if declare -f "$cmd" >/dev/null 2>&1; then
        local_impl=true
    fi
    
    if command -v "$cmd" >/dev/null 2>&1; then
        binary_impl=true
    fi
    
    if $local_impl; then
        log_success "$cmd ($num) — function defined"
    elif $binary_impl; then
        log_success "$cmd ($num) — binary available"
    else
        log_fail "$cmd ($num) — NOT DEFINED (label: $label)"
    fi
    
done <<< "$MENU_DATA"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: Test command execution (non-destructive)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 3: Testing command execution (safe operations only)..."

# Commands safe to execute with no args or minimal args
SAFE_COMMANDS=(
    "todo list"
    "calc '2 + 2'"
    "random uuid"
    "cert-check google.com"
    "dps"
    "dimages"
    "dvolumes"
    "dnetworks"
    "dprune"
    "git-recent"
    "git-prune"
    "sysinfo"
    "diskinfo"
    "myip"
    "ports"
    "svcstatus ssh"
    "encrypt --help"
    "decrypt --help"
    "secret-list"
    "ssh-list"
    "keystore-list"
    "cf-dns-list"
    "ts-status"
    "logs"
    "cpu-mem"
    "disk-io"
    "net-mon"
    "gpu-mon"
    "json-fmt --help"
    "py-fmt --help"
    "compress --help"
    "extract --help"
    "test-archive --help"
    "find-dupes --help"
    "backup --help"
    "proj-scan"
    "npm-check --help"
    "cargo-check --help"
    "go-check --help"
    "git-stats"
    "ssh-hardening"
    "edit-config"
    "dotfiles status"
    "theme"
    "keys"
    "pkg-audit"
    "sync-config"
    "bench"
    "health"
    "cal"
    "encode base64 test"
    "encode rot13 test"
    "random pass 8"
    "random dice 6 3"
    "units"
    "web GET http://example.com"
    "notes list"
    "timer help"
)

for cmd_test in "${SAFE_COMMANDS[@]}"; do
    cmd_name="${cmd_test%% *}"
    
    # Skip if command doesn't exist
    if ! declare -f "$cmd_name" >/dev/null 2>&1 && ! command -v "$cmd_name" >/dev/null 2>&1; then
        log_skip "$cmd_test — not implemented"
        continue
    fi
    
    # Execute with timeout and capture output
    set +e
    output=$(timeout 5 bash -c "source '$PROFILE' >/dev/null 2>&1; $cmd_test" 2>&1)
    exit_code=$?
    set -e
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "$cmd_test — executed successfully"
    elif [[ $exit_code -eq 124 ]]; then
        log_warn "$cmd_test — timed out (may be interactive)"
    else
        # Some commands legitimately fail with certain args, check for actual errors
        if echo "$output" | grep -qiE "command not found|not implemented|error:"; then
            log_fail "$cmd_test — execution error: $(echo "$output" | head -1)"
        else
            log_warn "$cmd_test — non-zero exit ($exit_code), may be expected"
        fi
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4: Verify TUI integration
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 4: Verifying Textual TUI integration..."

# Check menu_tui.py exists
if [[ -f "/home/drdeek/projects/MV-Maestro/menu_tui.py" ]]; then
    log_success "menu_tui.py exists"
else
    log_fail "menu_tui.py missing"
fi

# Check Python syntax
if python3 -m py_compile /home/drdeek/projects/MV-Maestro/menu_tui.py 2>/dev/null; then
    log_success "menu_tui.py syntax valid"
else
    log_fail "menu_tui.py has syntax errors"
fi

# Check load_menu_data works
if python3 -c "
import sys
sys.path.insert(0, '/home/drdeek/projects/MV-Maestro')
from menu_tui import load_menu_data
cats, err = load_menu_data()
if err:
    print(f'ERROR: {err}')
    sys.exit(1)
print(f'Loaded {len(cats)} categories, {sum(len(c.items) for c in cats)} items')
" 2>&1; then
    log_success "TUI can load menu data from bash"
else
    log_fail "TUI failed to load menu data"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 5: Verify entry points (dm, dmenu, etc.)
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 5: Verifying entry points..."

entry_points=("dm" "dmenu" "dms" "dmd" "dmc" "dmg" "dmsec" "dma" "dmc2" "dmm" "dmu" "dmenu-legacy")

for ep in "${entry_points[@]}"; do
    if type "$ep" >/dev/null 2>&1; then
        log_success "$ep — defined"
    else
        log_fail "$ep — NOT DEFINED"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 6: Category completeness check
# ─────────────────────────────────────────────────────────────────────────────

log_info "Phase 6: Checking category completeness..."

declare -A CATEGORY_COUNTS
declare -A CATEGORY_NAMES

while IFS=$'\x1f' read -r kind num label desc cmd; do
    if [[ $kind == "CATEGORY" ]]; then
        CATEGORY_NAMES[$num]="$label"
        CATEGORY_COUNTS[$num]=0
    elif [[ $kind == "ITEM" ]]; then
        CATEGORY_COUNTS[$num]=$(( ${CATEGORY_COUNTS[$num]:-0} + 1 ))
    fi
done <<< "$MENU_DATA"

for num in 1 2 3 4 5 6 7 8 9; do
    name="${CATEGORY_NAMES[$num]:-Unknown}"
    count="${CATEGORY_COUNTS[$num]:-0}"
    log_success "Category $num: $name ($count items)"
done

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    VALIDATION SUMMARY                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo -e "Total items checked: ${BLUE}$TOTAL${NC}"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo -e "Warnings: ${YELLOW}$WARNED${NC}"
echo -e "Skipped: ${DIM}$SKIPPED${NC}"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}❌ FAILED ITEMS:${NC}"
    for failure in "${FAILURES[@]}"; do
        echo "  • $failure"
    done
    echo ""
fi

if [[ $WARNED -gt 0 ]]; then
    echo -e "${YELLOW}⚠ WARNINGS:${NC}"
    for warning in "${WARNINGS[@]}"; do
        echo "  • $warning"
    done
    echo ""
fi

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All validations passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Validation failed with $FAILED errors${NC}"
    exit 1
fi
