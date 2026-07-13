# 🤖 Agent Development Guidelines

## Overview

This document defines the architectural requirements, design patterns, and development standards for the MV Maestro. It serves as the primary reference for maintaining, extending, and contributing to the codebase.

---

## 🏗️ Architecture Principles

### 1. Modularity

**Requirement:** All functionality must be organized into logical, independently testable modules.

**Structure:**
```
bash_enhanced.sh              # Entry point (orchestrator)
├── dynamic_core.sh           # Core system commands
├── dynamic_ext.sh            # Extended utilities
├── dynamic_menu.sh           # Menu data & navigation
├── dynamic_menu_addons.sh    # Additional command implementations
├── ssh_profile_setup.sh      # SSH wizard (standalone)
└── tailscale_helper.sh       # Tailscale helper (standalone)
```

**Rules:**
- ✅ Each module has a single responsibility
- ✅ No circular dependencies between modules
- ✅ Modules can be sourced independently for testing
- ✅ Shared utilities defined in `dynamic_core.sh` only
- ✅ Use `_` prefix for internal/helper functions (e.g., `_has`, `_die`)

**Example - Proper Module Separation:**

```bash
# ❌ BAD: Mixing concerns
git-root() { ... }
encrypt() { ... }
compress() { ... }

# ✅ GOOD: Organized by domain
# In dynamic_core.sh (security/crypto):
encrypt() { ... }
decrypt() { ... }

# In dynamic_menu_addons.sh (archive):
compress() { ... }
extract() { ... }

# In dynamic_core.sh (git):
git-root() { ... }
git-recent() { ... }
```

### 2. Smart Auto-Resolution

**Requirement:** Commands must intelligently handle missing dependencies, fallback options, and context-aware behavior.

**Patterns:**

#### Dependency Detection
```bash
# ✅ Check for tool availability before use
_has() { command -v "$1" >/dev/null 2>&1; }

# Example: calc with graceful fallback
calc() {
    local expr="$*"
    if _has bc; then
        echo "$expr = $(echo "$expr" | bc -l)"
    elif _has python3; then
        echo "$expr = $(python3 -c "print($expr)")"
    else
        echo "Error: Need bc or python3" >&2
        return 1
    fi
}
```

#### Context-Aware Behavior
```bash
# ✅ Choose encryption method based on context
encrypt() {
    local src="$1" recipient="${2:-}"
    
    if [[ -n "$recipient" ]]; then
        # Asymmetric mode: requires age
        _has age || { echo "Need 'age' for recipient encryption"; return 1; }
        age -e -r "$recipient" -o "${src}.age" "$src"
    else
        # Symmetric mode: prefer gpg, fallback to age
        if _has gpg; then
            gpg --symmetric --cipher AES256 -o "${src}.gpg" "$src"
        elif _has age; then
            age -p -o "${src}.age" "$src"
        else
            echo "Need 'gpg' or 'age'" >&2
            return 1
        fi
    fi
}
```

#### Format Auto-Detection
```bash
# ✅ Detect archive format from extension
extract() {
    case "$1" in
        *.tar.gz|*.tgz)   tar xzf "$1" ;;
        *.tar.bz2|*.tbz2) tar xjf "$1" ;;
        *.tar.xz|*.txz)   tar xJf "$1" ;;
        *.zip)            unzip "$1" ;;
        *)                echo "Unknown format"; return 1 ;;
    esac
}
```

### 3. --help Flag Requirement

**Requirement:** EVERY user-facing command MUST implement `--help` / `-h` flag with comprehensive documentation.

**Template:**
```bash
command-name() {
    local arg="${1:-}"
    
    # ✅ Help check at the beginning
    [[ "$arg" == "--help" || "$arg" == "-h" ]] && {
        cat <<'HELP'
Usage: command-name <arg1> [arg2] [options]

Brief description of what the command does.

Arguments:
  arg1          Required argument description
  arg2          Optional argument (default: value)

Options:
  --help, -h    Show this help message
  --flag        Description of optional flag
  --option VAL  Description of option taking value

Environment:
  ENV_VAR       Description of required/optional env vars

Examples:
  command-name value1               # Basic usage
  command-name value1 value2        # With optional arg
  command-name value1 --flag        # With flag
  command-name value1 --option foo  # With option

Related:
  related-command  # Related command for workflow
HELP
        return 0
    }
    
    # Actual implementation follows...
    [[ -z "$arg" ]] && { echo "Usage: command-name <arg1>"; return 1; }
    # ... rest of implementation
}
```

**Help Quality Standards:**
- ✅ Must include: Usage syntax, Arguments, Options, Examples
- ✅ Must show: What the command does, not just how to call it
- ✅ Must list: Environment variables if applicable
- ✅ Must provide: At least 2-3 practical examples
- ✅ Should mention: Related commands for common workflows

**❌ BAD Help:**
```bash
encrypt() {
    [[ "$1" == "--help" ]] && { echo "encrypt <file>"; return 0; }
    # ...
}
```

**✅ GOOD Help:**
```bash
encrypt() {
    [[ "$1" == "--help" ]] && {
        cat <<'HELP'
Usage: encrypt <path> [recipient] [--armor] [--sign]

Encrypt files using age (asymmetric) or GPG (symmetric).

Arguments:
  path          File or directory to encrypt
  recipient     Age public key for asymmetric encryption (optional)

Options:
  --armor       Output ASCII-armored format (.asc)
  --sign        Sign with GPG before encryption
  --passphrase  Force symmetric passphrase mode

Encryption Modes:
  • With recipient: age asymmetric encryption
  • Without recipient: GPG/age symmetric (uses AGE_PASSPHRASE)

Environment:
  AGE_PASSPHRASE    Passphrase for symmetric encryption

Examples:
  encrypt secret.txt                      # Symmetric (GPG/age)
  encrypt config.yaml user@example.age    # Asymmetric (age)
  encrypt mydir --armor                   # Create .asc file
HELP
        return 0
    }
    # ... implementation
}
```

### 4. Menu Descriptions & Interactivity

**Requirement:** All menu items must have clear, informative descriptions explaining capabilities and interactivity.

**Menu Data Structure (in `dynamic_menu.sh`):**
```bash
MENU_CATEGORY=(
    "🎯 Label|Description of what it does|command-name|"
    "📊 Stats|Shows repository statistics|git-stats|"
)
```

**Description Standards:**
- ✅ **Be specific**: "Format Python files with black/ruff" NOT "Python tools"
- ✅ **Mention interactivity**: "Interactive host setup wizard" NOT "SSH config"
- ✅ **Highlight features**: "Auto-detect format, smart excludes" NOT "Compress files"
- ✅ **Note requirements**: "Requires Textual TUI" if applicable
- ✅ **Keep concise**: One sentence, under 80 characters when possible

**❌ BAD Descriptions:**
```bash
MENU_DEV=(
    "🐍 Python|Python tools|py-fmt|"           # Too vague
    "📦 Node|Node.js stuff|npm-check|"         # Unprofessional
    "📝 JSON|JSON things|json-fmt|"            # Meaningless
)
```

**✅ GOOD Descriptions:**
```bash
MENU_DEV=(
    "🐍 Python|Format (black/ruff), lint, venv management|py-fmt|"
    "📦 Node.js|npm/yarn/pnpm dependency audit & outdated check|npm-check|"
    "📝 JSON Tools|Format, lint, extract/set values, validate|json-fmt|"
)
```

**Interactivity Flags:**
Commands that open interactive interfaces should be marked in metadata:

```bash
# In dynamic_menu.sh, track which commands are interactive
declare -A MENU_INTERACTIVE=(
    ["docker-tui"]="true"
    ["menu_tui"]="true"
    ["ssh-add-key"]="true"
    ["ts-status"]="false"  # Non-interactive output
)

# In dynamic_menu.sh launch logic
_launch_command() {
    local cmd="$1"
    if [[ "${MENU_INTERACTIVE[$cmd]}" == "true" ]]; then
        # Hand off TTY properly for interactive apps
        script -q -c "$cmd" /dev/null
    else
        $cmd
    fi
}
```

### 5. Feature Features Documentation

**Requirement:** Every feature must document what's included and available.

**Include in function comments:**
```bash
# ============================================================================
# compress - Compress files/directories with smart excludes
# ============================================================================
#
# Features:
#   • Auto-detect compression algorithm (gzip, bzip2, xz, zip)
#   • Smart excludes: node_modules, .git, __pycache__
#   • Progress indication for large archives
#   • Custom exclude patterns via --no-excludes flag
#   • Fast/best compression modes
#
# Supported Formats:
#   .tar.gz  (default)  gzip compressed tar
#   .tar.bz2            bzip2 compressed tar
#   .tar.xz             xz compressed tar (best compression)
#   .zip                zip archive
#
# Interactivity:
#   Non-interactive CLI, suitable for scripts and automation
#
# Dependencies:
#   Required: tar, gzip/bzip2/xz/zip (at least one)
#   Optional: pv (for progress bar, not implemented)
#
# Examples:
#   compress mydir                    # Creates mydir.tar.gz
#   compress mydir zip                # Creates mydir.zip
#   compress data --best              # Uses xz for max compression
#   compress project --no-excludes    # Include everything
#
# Related:
#   extract      - Extract archives
#   test-archive - Verify archive integrity
#   backup       - Timestamped backups
# ============================================================================
compress() {
    # Implementation...
}
```

---

## 🛠️ Adding New Features

### Step 1: Determine Module Location

**Question:** What category does this feature belong to?

| Category | Module |
|----------|--------|
| Security, Crypto, SSH, Git, Docker core | `dynamic_core.sh` |
| Archive, Dev Tools, Utilities | `dynamic_menu_addons.sh` |
| Extended system utilities | `dynamic_ext.sh` |
| Wizards (SSH, Tailscale setup) | New file in `modules/` |

**Decision Tree:**
```
Is it a wizard/interactive setup? 
  → Yes: Create new module (e.g., wizard_name.sh)
  → No: Continue
  
Is it security/crypto/SSH/Git/Docker?
  → Yes: dynamic_core.sh
  
Is it development tools (Python, Node, etc.)?
  → Yes: dynamic_menu_addons.sh
  
Is it system-wide utility?
  → Yes: dynamic_ext.sh
```

### Step 2: Implement Command

**Template:**
```bash
# ============================================================================
# command-name - Brief feature summary
# ============================================================================
#
# Features:
#   • List key capability 1
#   • List key capability 2
#
# Interactivity:
#   Interactive wizard / Non-interactive CLI / TUI application
#
# Dependencies:
#   Required: tool1, tool2
#   Optional: tool3 (enables advanced features)
#
# Examples:
#   command-name arg1                 # Basic usage
#   command-name arg1 --flag          # With option
#
# ============================================================================
command-name() {
    local arg1="${1:-}" arg2="${2:-}"
    
    # ✅ Help implementation (REQUIRED)
    [[ "$arg1" == "--help" || "$arg1" == "-h" ]] && {
        cat <<'HELP'
Usage: command-name <arg1> [arg2] [options]

Detailed description of what this command does.

Arguments:
  arg1          Required argument description
  arg2          Optional argument (default: value)

Options:
  --help, -h    Show this help message
  --flag        Enable optional feature
  --option VAL  Set option value

Features:
  • Capability 1 explanation
  • Capability 2 explanation

Dependencies:
  Required: tool1, tool2
  Optional: tool3

Examples:
  command-name value1                 # Basic usage
  command-name value1 value2          # With optional arg
  command-name value1 --flag          # With flag
  command-name value1 --option foo    # With option

Related:
  related-cmd  - Related functionality
HELP
        return 0
    }
    
    # ✅ Input validation
    [[ -z "$arg1" ]] && { echo "Usage: command-name <arg1>"; return 1; }
    
    # ✅ Dependency checking with auto-resolution
    _has tool1 || { echo "Error: Need 'tool1'"; return 1; }
    
    # ✅ Fallback handling
    if _has tool1; then
        tool1 --option "$arg1"
    elif _has tool2; then
        tool2 "$arg1"  # Fallback
    else
        echo "Error: Need tool1 or tool2" >&2
        return 1
    fi
}
```

### Step 3: Add to Menu

Edit `dynamic_menu.sh`:

```bash
# Find appropriate category and add entry
MENU_DEV=(
    # ... existing entries ...
    
    # ✅ Add your new command
    "🆕 New Tool|Clear description of features and interactivity|command-name|"
)

# ✅ Update MENU_CATEGORIES count if needed
# MENU_CATEGORIES=['2']='💻 Development Tools|MENU_DEV'
```

**Menu Entry Format:**
```
Label|Description|command-name|additional_metadata
```

**Best Practices:**
- Use emoji that matches category theme
- Keep label under 20 characters
- Description should explain value proposition
- Include interactivity indicator if applicable

### Step 4: Test

```bash
# Test help flag
command-name --help

# Test basic functionality
command-name test-args

# Validate against menu
./tests/validate_menu.sh

# Check for syntax errors
bash -n modules/dynamic_core.sh  # Or appropriate module
```

---

## 🗑️ Removing Features

### Safe Removal Process

1. **Remove from menu first:**
   ```bash
   # In dynamic_menu.sh, comment out or delete entry
   # "Old Tool|Description|old-cmd|"
   ```

2. **Verify no dependencies:**
   ```bash
   grep -r "old-cmd" modules/*.sh bash_enhanced.sh
   # Ensure no other commands reference it
   ```

3. **Remove implementation:**
   ```bash
   # Delete function from module file
   # Keep backup for 30 days
   cp modules/dynamic_core.sh modules/.bak/dynamic_core.sh.old
   ```

4. **Update documentation:**
   ```bash
   # Remove from README.md command reference
   # Update AGENTS.md if removal affects architecture
   ```

5. **Validate remaining system:**
   ```bash
   ./tests/validate_menu.sh
   source ~/.bashrc  # Ensure no errors
   ```

---

## 🔄 Updating Features

### Version Control Strategy

**File Naming Convention:**
```
module_name.sh              # Current version
module_name.sh.bak.YYYYMMDD # Backup with date
module_name.v2.sh           # Major version update
```

### Update Checklist

**For minor updates (bug fixes, optimizations):**
- [ ] Test current behavior
- [ ] Make changes
- [ ] Test updated behavior
- [ ] Run validation suite
- [ ] Update function comments if behavior changed
- [ ] Commit with descriptive message

**For major updates (new features, breaking changes):**
- [ ] Create backup: `cp module.sh module.sh.bak.$(date +%Y%m%d)`
- [ ] Implement in separate branch/file
- [ ] Test thoroughly
- [ ] Update menu descriptions
- [ ] Update README.md
- [ ] Notify users of breaking changes
- [ ] Deprecate old version gradually

### Deprecation Pattern

```bash
# ✅ Graceful deprecation
old-command() {
    [[ "$1" == "--help" || "$1" == "-h" ]] && {
        cat <<'HELP'
⚠️ DEPRECATED: Use new-command instead

This command will be removed in v3.0.

Migration:
  old-command arg1 arg2    →  new-command --option1 arg1 --option2 arg2

See 'new-command --help' for updated usage.
HELP
        return 0
    }
    
    _warn "old-command is deprecated. Use new-command instead."
    # Call new implementation
    new-command "$@"
}
```

---

## 🧪 Testing Requirements

### Unit Testing

Every command must pass these tests:

```bash
# Test 1: Help flag works
command --help >/dev/null 2>&1 && echo "PASS" || echo "FAIL"

# Test 2: Usage message on missing args
command 2>&1 | grep -qi "usage" && echo "PASS" || echo "FAIL"

# Test 3: Graceful error handling
command invalid-arg 2>&1 | grep -qi "error\|not found" && echo "PASS" || echo "FAIL"

# Test 4: Dependency detection
_has some-tool && command || echo "Skipped (missing dependency)"
```

### Integration Testing

Run full validation suite:
```bash
./tests/validate_menu.sh
```

Expected results:
- ✅ All 68+ commands load without errors
- ✅ All `--help` flags work
- ✅ All menu items are accessible
- ✅ No syntax errors in any module

### Regression Testing

After any change:
```bash
# 1. Source fresh shell
bash --norc --noprofile -i

# 2. Load enhanced profile
source ~/MV-Maestro/bash_enhanced.sh

# 3. Test affected commands
affected-command --help
related-command --help

# 4. Run validation
./tests/validate_menu.sh
```

---

## 📋 Code Style Guide

### Function Naming

**User-facing commands:** Lowercase, hyphen-separated
```bash
✅ git-root
✅ json-fmt
✅ ssh-add-key
❌ git_root
❌ JsonFmt
❌ SSHAddKey
```

**Internal helpers:** Underscore prefix
```bash
✅ _has
✅ _die
✅ _info
✅ _warn
❌ has
❌ Die
❌ info
```

### Variable Naming

```bash
# Local variables
local dir="${1:-.}"
local max_depth="${2:-3}"

# Global constants (UPPERCASE)
readonly _SECRETS_DIR="$HOME/.secrets"
readonly _MENU_TUI_PY="$BASH_SOURCE[0]%/*}/menu_tui.py"

# Arrays
declare -a MENU_CATEGORY=(...)
declare -A MENU_INTERACTIVE=(...)
```

### Error Handling

```bash
# ✅ Consistent error pattern
[[ -z "$arg" ]] && { echo "Usage: cmd <arg>"; return 1; }
[[ ! -e "$path" ]] && { _die "Not found: $path"; return 1; }

_has required-tool || { _die "Need 'required-tool'"; return 1; }

# ✅ Success messages
_ok "Completed: $result"
_info "Processing $item..."
```

### Comments

```bash
# ✅ Section headers with borders
# ─────────────────────────────────────────────────────────────────────────────
# SECTION NAME
# ─────────────────────────────────────────────────────────────────────────────

# ✅ Detailed function documentation
# ============================================================================
# function-name - One line summary
# ============================================================================
# Features:
#   • Detail 1
#   • Detail 2
#
# Interactivity:
#   Description
#
# Dependencies:
#   Required: tool1
#   Optional: tool2
#
# Examples:
#   command example
# ============================================================================

# ✅ Inline comments for complex logic
tar -czf "$out" "$target" \
    --exclude='node_modules' \  # Skip JS dependencies
    --exclude='.git' \          # Skip version control
    --exclude='__pycache__'     # Skip Python cache
```

---

## 🔒 Security Considerations

### Secret Handling

```bash
# ✅ NEVER hardcode secrets
❌ password="secret123"

# ✅ Use environment variables or encrypted storage
password="${AGE_PASSPHRASE:-}"  # User provides via env
# OR
secret-get api-key              # From encrypted store

# ✅ Never log sensitive data
❌ echo "Using password: $password"
✅ _info "Authenticating..."
```

### File Permissions

```bash
# ✅ Secure directory creation
mkdir -p "$HOME/.secrets"
chmod 700 "$HOME/.secrets"

# ✅ Secure file operations
umask 077
gpg --symmetric -o secret.gpg secret.txt
```

### Command Injection Prevention

```bash
# ✅ Quote all variables
❌ eval "$user_input"
✅ "$command" "$safe_arg"

# ✅ Validate input
[[ "$filename" =~ ^[a-zA-Z0-9._-]+$ ]] || { _die "Invalid filename"; return 1; }
```

---

## 📞 Support & Maintenance

### Issue Reporting

When reporting issues, include:
```bash
# System info
bash --version
uname -a

# Enhanced profile status
source ~/MV-Maestro/bash_enhanced.sh
dynhelp | head -5

# Problem description
# Steps to reproduce
# Expected vs actual behavior
```

### Performance Optimization

Monitor command performance:
```bash
# Slow commands (>1s) should be optimized
time compress large-directory

# Use background processing for long tasks
compress big-dir &
PID=$!
echo "Compression running (PID: $PID)"
wait $PID && _ok "Done" || _die "Failed"
```

---

**Version:** 2.0.0  
**Last Updated:** October 2024  
**Maintained By:** @drdeeks
