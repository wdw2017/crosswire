#!/usr/bin/env bash
# install-comms.sh — Standalone installer for claude-instance-comms
# Usage: ./install-comms.sh [--mode hub|join] [--name NAME] [--hub PATH] [--agent claude|codex|other|skip] [--install-dir DIR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"

# --- Color support ---

if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    BOLD='' DIM='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

# --- Output helpers ---

info()    { printf "${CYAN}==>${RESET} %s\n" "$*"; }
success() { printf "${GREEN}==>${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}Warning:${RESET} %s\n" "$*"; }
error()   { printf "${RED}Error:${RESET} %s\n" "$*" >&2; }
fatal()   { error "$@"; exit 1; }

header() {
    echo ""
    printf "${BOLD}%s${RESET}\n" "$*"
    printf "${DIM}%s${RESET}\n" "$(echo "$*" | sed 's/./-/g')"
}

# --- Prompt helpers ---

# ask VARNAME "prompt" "default"
ask() {
    local varname="$1" prompt="$2" default="${3:-}"
    if [[ -n "$default" ]]; then
        printf "${BOLD}%s${RESET} [%s]: " "$prompt" "$default"
    else
        printf "${BOLD}%s${RESET}: " "$prompt"
    fi
    local answer
    read -r answer
    answer="${answer:-$default}"
    eval "$varname=\"\$answer\""
}

# confirm "prompt" (returns 0 for yes, 1 for no)
confirm() {
    local prompt="$1"
    printf "${BOLD}%s${RESET} [Y/n]: " "$prompt"
    local answer
    read -r answer
    answer="${answer:-y}"
    local answer_lower
    answer_lower="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    [[ "$answer_lower" == "y" || "$answer_lower" == "yes" ]]
}

# menu VARNAME "prompt" option1 option2 ...
menu() {
    local varname="$1" prompt="$2"
    shift 2
    local options=("$@")
    echo ""
    printf "${BOLD}%s${RESET}\n" "$prompt"
    local i=1
    for opt in "${options[@]}"; do
        printf "  ${CYAN}%d)${RESET} %s\n" "$i" "$opt"
        ((i++))
    done
    printf "Choice: "
    local choice
    read -r choice
    choice="${choice:-1}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        eval "$varname=\"\$choice\""
    else
        eval "$varname=1"
    fi
}

# --- Parse CLI flags ---

ARG_MODE="" ARG_NAME="" ARG_HUB="" ARG_AGENT="" ARG_INSTALL_DIR="" ARG_HUB_HOST=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)        ARG_MODE="$2"; shift 2 ;;
        --name)        ARG_NAME="$2"; shift 2 ;;
        --hub)         ARG_HUB="$2"; shift 2 ;;
        --hub-host)    ARG_HUB_HOST="$2"; shift 2 ;;
        --agent)       ARG_AGENT="$2"; shift 2 ;;
        --install-dir) ARG_INSTALL_DIR="$2"; shift 2 ;;
        --help|-h)
            cat <<'USAGE'
install-comms.sh — Installer for claude-instance-comms

Usage: ./install-comms.sh [OPTIONS]

Options:
  --mode hub|join       Create a new hub or join an existing one
  --name NAME           Instance name (default: hostname)
  --hub PATH            Hub directory path (for create) or location (for join)
  --hub-host USER@HOST  Remote hub host (e.g. user@server)
  --agent TYPE          Agent integration: claude, codex, other, skip
  --install-dir DIR     Where to install the comms CLI (default: current dir)
  --help                Show this help

Without flags, runs interactively with sensible defaults.
USAGE
            exit 0
            ;;
        *) fatal "Unknown option: $1. Run: ./install-comms.sh --help" ;;
    esac
done

# ============================================================
# Step 1: Detect environment
# ============================================================

header "Step 1: Checking environment"

# JSON parser
HAS_JQ=false HAS_PYTHON3=false
command -v jq &>/dev/null && HAS_JQ=true
command -v python3 &>/dev/null && HAS_PYTHON3=true

if $HAS_JQ; then
    success "jq found (preferred JSON parser)"
elif $HAS_PYTHON3; then
    success "python3 found (JSON parser fallback)"
else
    fatal "jq or python3 required for JSON parsing. Install one:\n  macOS: brew install jq\n  Linux: sudo apt install jq"
fi

# SSH
HAS_SSH=false
if command -v ssh &>/dev/null; then
    HAS_SSH=true
    success "ssh found"
else
    warn "ssh not found — remote hubs won't work"
fi

# SSH keys
SSH_KEY_PATH=""
if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
    success "SSH key found: $SSH_KEY_PATH"
elif [[ -f "$HOME/.ssh/id_rsa" ]]; then
    SSH_KEY_PATH="$HOME/.ssh/id_rsa"
    success "SSH key found: $SSH_KEY_PATH"
else
    warn "No SSH key found (~/.ssh/id_ed25519 or ~/.ssh/id_rsa)"
    if $HAS_SSH; then
        if confirm "Generate an ed25519 SSH key for comms?"; then
            info "Generating SSH key..."
            ssh-keygen -t ed25519 -C "claude-instance-comms" -f "$HOME/.ssh/id_ed25519" -N ""
            SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
            success "SSH key generated: $SSH_KEY_PATH"
        else
            info "Skipping SSH key generation"
        fi
    fi
fi

# OS detection
OS="unknown"
case "$(uname -s)" in
    Darwin) OS="macos"; success "Platform: macOS" ;;
    Linux)  OS="linux"; success "Platform: Linux" ;;
    *)      OS="$(uname -s)"; warn "Unrecognized platform: $OS" ;;
esac

# Verify repo files exist
for f in bin/comms lib/transport.sh templates/comms.json.template templates/CLAUDE.md.snippet templates/AGENTS.md.snippet; do
    [[ -f "$SCRIPT_DIR/$f" ]] || fatal "Required file not found: $SCRIPT_DIR/$f\nAre you running this from the cloned repo directory?"
done
success "Repo files verified"

# ============================================================
# Step 2: Choose mode
# ============================================================

header "Step 2: Choose mode"

MODE=""
if [[ -n "$ARG_MODE" ]]; then
    case "$ARG_MODE" in
        hub|create)  MODE="hub" ;;
        join)        MODE="join" ;;
        *)           fatal "Invalid --mode: $ARG_MODE (expected: hub or join)" ;;
    esac
    info "Mode: $MODE (from --mode flag)"
else
    menu MODE "What would you like to do?" \
        "Create a new hub" \
        "Join an existing hub"
    case "$MODE" in
        1) MODE="hub" ;;
        2) MODE="join" ;;
    esac
fi

# ============================================================
# Step 3a: CREATE HUB
# ============================================================

HUB_PATH="" HUB_HOST="" HUB_LOCAL="true" INSTANCE_NAME="" PEERS=()

if [[ "$MODE" == "hub" ]]; then
    header "Step 3: Create a new hub"

    # Hub directory path
    if [[ -n "$ARG_HUB" ]]; then
        HUB_PATH="$ARG_HUB"
    else
        ask HUB_PATH "Hub directory path" "./.comms"
    fi

    # Local or remote?
    HUB_REMOTE_CHOICE=""
    if [[ -n "$ARG_HUB_HOST" ]]; then
        HUB_HOST="$ARG_HUB_HOST"
        HUB_LOCAL="false"
    else
        menu HUB_REMOTE_CHOICE "Hub location:" \
            "Local (this machine)" \
            "Remote (another machine via SSH)"
        if [[ "$HUB_REMOTE_CHOICE" == "2" ]]; then
            if ! $HAS_SSH; then
                fatal "SSH is required for remote hubs but ssh was not found"
            fi
            ask HUB_HOST "Remote host (user@host)" ""
            [[ -z "$HUB_HOST" ]] && fatal "Remote host is required"
            HUB_LOCAL="false"
        fi
    fi

    # Create hub structure
    if [[ "$HUB_LOCAL" == "true" ]]; then
        # Resolve to absolute path
        if [[ "$HUB_PATH" != /* ]]; then
            HUB_PATH="$(cd "$(dirname "$HUB_PATH")" 2>/dev/null && pwd)/$(basename "$HUB_PATH")" || HUB_PATH="$(pwd)/$HUB_PATH"
        fi

        if [[ -d "$HUB_PATH/registry" ]]; then
            warn "Hub already exists at $HUB_PATH"
            if ! confirm "Continue with existing hub?"; then
                fatal "Aborted"
            fi
        else
            info "Creating hub at $HUB_PATH..."
            mkdir -p "$HUB_PATH"/{registry,tmp,files}
            success "Hub created at $HUB_PATH"
        fi
    else
        info "Creating hub on $HUB_HOST at $HUB_PATH..."
        ssh -o ConnectTimeout=10 -o BatchMode=yes "$HUB_HOST" \
            "mkdir -p '$HUB_PATH'/{registry,tmp,files}" 2>/dev/null || \
            fatal "Cannot reach $HUB_HOST. Check SSH config and key-based auth"
        success "Hub created on $HUB_HOST:$HUB_PATH"
    fi

    # Instance name
    DEFAULT_NAME="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "node1")"
    DEFAULT_NAME="$(echo "$DEFAULT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' .' '-')"
    if [[ -n "$ARG_NAME" ]]; then
        INSTANCE_NAME="$ARG_NAME"
    else
        ask INSTANCE_NAME "Instance name for this machine" "$DEFAULT_NAME"
    fi

    # Validate instance name (alphanumeric + hyphens only)
    if [[ ! "$INSTANCE_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        fatal "Invalid instance name: '$INSTANCE_NAME' (use letters, numbers, hyphens)"
    fi

    # Register self in hub
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [[ "$HUB_LOCAL" == "true" ]]; then
        REG_JSON="{\"name\":\"$INSTANCE_NAME\",\"registered\":\"$NOW\",\"hubLocal\":true}"
    else
        REG_JSON="{\"name\":\"$INSTANCE_NAME\",\"registered\":\"$NOW\",\"hubLocal\":false,\"hubAccess\":\"ssh://$HUB_HOST:$HUB_PATH\"}"
    fi

    if [[ "$HUB_LOCAL" == "true" ]]; then
        if [[ -f "$HUB_PATH/registry/${INSTANCE_NAME}.json" ]]; then
            warn "Instance '$INSTANCE_NAME' already registered in hub"
        else
            echo "$REG_JSON" > "$HUB_PATH/registry/${INSTANCE_NAME}.json"
            success "Registered '$INSTANCE_NAME' in hub"
        fi
        # Create inbox dirs
        mkdir -p "$HUB_PATH/to-${INSTANCE_NAME}"/{pending,done,sent}
    else
        local_check="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" "ls '$HUB_PATH/registry/${INSTANCE_NAME}.json' 2>/dev/null" || true)"
        if [[ -n "$local_check" ]]; then
            warn "Instance '$INSTANCE_NAME' already registered in hub"
        else
            ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" \
                "echo '$REG_JSON' > '$HUB_PATH/registry/${INSTANCE_NAME}.json'"
            success "Registered '$INSTANCE_NAME' in hub"
        fi
        ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" \
            "mkdir -p '$HUB_PATH/to-${INSTANCE_NAME}'/{pending,done,sent}"
    fi

fi

# ============================================================
# Step 3b: JOIN HUB
# ============================================================

if [[ "$MODE" == "join" ]]; then
    header "Step 3: Join an existing hub"

    # Hub location
    HUB_SPEC=""
    if [[ -n "$ARG_HUB" ]]; then
        HUB_SPEC="$ARG_HUB"
    else
        ask HUB_SPEC "Hub location (local path or user@host:/path)" ""
        [[ -z "$HUB_SPEC" ]] && fatal "Hub location is required"
    fi

    # Parse hub spec
    if [[ "$HUB_SPEC" == *:* ]]; then
        HUB_HOST="${HUB_SPEC%%:*}"
        HUB_PATH="${HUB_SPEC#*:}"
        HUB_LOCAL="false"
    else
        HUB_HOST=""
        HUB_LOCAL="true"
        # Resolve to absolute path
        if [[ "$HUB_SPEC" != /* ]]; then
            HUB_PATH="$(cd "$HUB_SPEC" 2>/dev/null && pwd)" || HUB_PATH="$(pwd)/$HUB_SPEC"
        else
            HUB_PATH="$HUB_SPEC"
        fi
    fi

    # Test connectivity
    info "Testing hub connectivity..."
    if [[ "$HUB_LOCAL" == "true" ]]; then
        [[ -d "$HUB_PATH/registry" ]] || fatal "Hub not found at $HUB_PATH (no registry/ directory)"
        success "Hub found at $HUB_PATH"
    else
        if ! $HAS_SSH; then
            fatal "SSH is required for remote hubs but ssh was not found"
        fi
        ssh -o ConnectTimeout=10 -o BatchMode=yes "$HUB_HOST" "ls '$HUB_PATH/registry/' >/dev/null" 2>/dev/null || \
            fatal "Cannot reach hub at $HUB_HOST:$HUB_PATH. Check SSH config"
        success "Hub reachable at $HUB_HOST:$HUB_PATH"
    fi

    # Show existing peers
    info "Existing peers:"
    if [[ "$HUB_LOCAL" == "true" ]]; then
        EXISTING_PEERS="$(ls "$HUB_PATH/registry/"*.json 2>/dev/null | xargs -I{} basename {} .json || true)"
    else
        EXISTING_PEERS="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" "ls '$HUB_PATH/registry/'*.json 2>/dev/null | xargs -I{} basename {} .json" 2>/dev/null || true)"
    fi

    if [[ -n "$EXISTING_PEERS" ]]; then
        while IFS= read -r peer; do
            printf "  - %s\n" "$peer"
            PEERS+=("$peer")
        done <<< "$EXISTING_PEERS"
    else
        echo "  (none)"
    fi

    # Instance name
    DEFAULT_NAME="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "node1")"
    DEFAULT_NAME="$(echo "$DEFAULT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' .' '-')"
    if [[ -n "$ARG_NAME" ]]; then
        INSTANCE_NAME="$ARG_NAME"
    else
        ask INSTANCE_NAME "Instance name for this machine" "$DEFAULT_NAME"
    fi

    # Validate name
    if [[ ! "$INSTANCE_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        fatal "Invalid instance name: '$INSTANCE_NAME' (use letters, numbers, hyphens)"
    fi

    # Check uniqueness
    for peer in "${PEERS[@]}"; do
        if [[ "$peer" == "$INSTANCE_NAME" ]]; then
            fatal "'$INSTANCE_NAME' already registered. Use a different name"
        fi
    done

    # Register in hub
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [[ "$HUB_LOCAL" == "true" ]]; then
        REG_JSON="{\"name\":\"$INSTANCE_NAME\",\"registered\":\"$NOW\",\"hubLocal\":true}"
        echo "$REG_JSON" > "$HUB_PATH/registry/${INSTANCE_NAME}.json"
        mkdir -p "$HUB_PATH/to-${INSTANCE_NAME}"/{pending,done,sent}
    else
        REG_JSON="{\"name\":\"$INSTANCE_NAME\",\"registered\":\"$NOW\",\"hubLocal\":false,\"hubAccess\":\"ssh://$HUB_HOST:$HUB_PATH\"}"
        ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" \
            "echo '$REG_JSON' > '$HUB_PATH/registry/${INSTANCE_NAME}.json'" 2>/dev/null || \
            fatal "Failed to register in hub"
        ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" \
            "mkdir -p '$HUB_PATH/to-${INSTANCE_NAME}'/{pending,done,sent}" 2>/dev/null || \
            fatal "Failed to create inbox dirs"
    fi

    success "Registered '$INSTANCE_NAME' in hub"
    success "Created inbox directories for '$INSTANCE_NAME'"
fi

# ============================================================
# Step 4: Install CLI
# ============================================================

header "Step 4: Install CLI"

# Determine install location
INSTALL_DIR=""
if [[ -n "$ARG_INSTALL_DIR" ]]; then
    INSTALL_DIR="$ARG_INSTALL_DIR"
else
    ask INSTALL_DIR "Install location (directory for comms CLI + config)" "$(pwd)"
fi

# Resolve to absolute path
if [[ "$INSTALL_DIR" != /* ]]; then
    INSTALL_DIR="$(cd "$INSTALL_DIR" 2>/dev/null && pwd)" || INSTALL_DIR="$(pwd)/$INSTALL_DIR"
fi

# Create directory if needed
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib"

# Copy CLI (skip if installing into the repo itself)
if [[ "$(cd "$INSTALL_DIR" && pwd)" == "$(cd "$SCRIPT_DIR" && pwd)" ]]; then
    success "Installing into repo directory — bin/comms and lib/transport.sh already in place"
    chmod +x "$INSTALL_DIR/bin/comms"
else
    if [[ -f "$INSTALL_DIR/bin/comms" ]]; then
        warn "bin/comms already exists at $INSTALL_DIR/bin/"
        if confirm "Overwrite with latest version?"; then
            cp "$SCRIPT_DIR/bin/comms" "$INSTALL_DIR/bin/comms"
            success "Updated bin/comms"
        else
            info "Keeping existing bin/comms"
        fi
    else
        cp "$SCRIPT_DIR/bin/comms" "$INSTALL_DIR/bin/comms"
        success "Installed bin/comms"
    fi
    chmod +x "$INSTALL_DIR/bin/comms"

    # Copy transport lib
    if [[ -f "$INSTALL_DIR/lib/transport.sh" ]]; then
        # Always update the transport lib — it must match the CLI
        cp "$SCRIPT_DIR/lib/transport.sh" "$INSTALL_DIR/lib/transport.sh"
        success "Updated lib/transport.sh"
    else
        cp "$SCRIPT_DIR/lib/transport.sh" "$INSTALL_DIR/lib/transport.sh"
        success "Installed lib/transport.sh"
    fi
fi

# Generate comms.json
CONFIG_FILE="$INSTALL_DIR/comms.json"

# Build peers JSON
PEERS_JSON="[]"
if [[ ${#PEERS[@]} -gt 0 ]]; then
    if $HAS_JQ; then
        PEERS_JSON="$(printf '%s\n' "${PEERS[@]}" | jq -R . | jq -s .)"
    elif $HAS_PYTHON3; then
        PEERS_JSON="$(python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" "${PEERS[@]}")"
    fi
fi

# Determine default peer
DEFAULT_PEER="null"
if [[ ${#PEERS[@]} -eq 1 ]]; then
    DEFAULT_PEER="\"${PEERS[0]}\""
fi

# Hub host JSON value
HUB_HOST_JSON="null"
[[ -n "$HUB_HOST" ]] && HUB_HOST_JSON="\"$HUB_HOST\""

if [[ -f "$CONFIG_FILE" ]]; then
    warn "comms.json already exists at $CONFIG_FILE"
    if confirm "Overwrite with new configuration?"; then
        cat > "$CONFIG_FILE" <<ENDJSON
{
  "self": "$INSTANCE_NAME",
  "hub": {
    "path": "$HUB_PATH",
    "host": $HUB_HOST_JSON,
    "local": $HUB_LOCAL
  },
  "peers": $PEERS_JSON,
  "defaultPeer": $DEFAULT_PEER
}
ENDJSON
        success "Updated comms.json"
    else
        info "Keeping existing comms.json"
    fi
else
    cat > "$CONFIG_FILE" <<ENDJSON
{
  "self": "$INSTANCE_NAME",
  "hub": {
    "path": "$HUB_PATH",
    "host": $HUB_HOST_JSON,
    "local": $HUB_LOCAL
  },
  "peers": $PEERS_JSON,
  "defaultPeer": $DEFAULT_PEER
}
ENDJSON
    success "Generated comms.json"
fi

# Create a convenience wrapper 'comms' at the install root
if [[ -f "$INSTALL_DIR/comms" ]]; then
    info "Convenience wrapper already exists at $INSTALL_DIR/comms"
else
    cat > "$INSTALL_DIR/comms" <<'WRAPPER'
#!/usr/bin/env bash
# Convenience wrapper — delegates to bin/comms
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/comms" "$@"
WRAPPER
    chmod +x "$INSTALL_DIR/comms"
    success "Created convenience wrapper: $INSTALL_DIR/comms"
fi

# ============================================================
# Step 5: Agent integration
# ============================================================

header "Step 5: Agent integration"

MARKER_START="<!-- claude-instance-comms:start -->"
MARKER_END="<!-- claude-instance-comms:end -->"

# Inject a snippet into a file between markers (idempotent)
inject_snippet() {
    local target_file="$1"
    local snippet_file="$2"

    # Create file if it doesn't exist
    if [[ ! -f "$target_file" ]]; then
        mkdir -p "$(dirname "$target_file")"
        touch "$target_file"
    fi

    # Check if markers already exist
    if grep -qF "$MARKER_START" "$target_file" 2>/dev/null; then
        warn "Comms snippet already present in $target_file"
        if confirm "Replace existing snippet?"; then
            # Remove old snippet (between markers inclusive) and inject new
            local tmp_file="${target_file}.comms-tmp.$$"
            awk -v start="$MARKER_START" -v end="$MARKER_END" '
                $0 == start { skip=1; next }
                $0 == end   { skip=0; next }
                !skip       { print }
            ' "$target_file" > "$tmp_file"
            # Append new snippet
            echo "" >> "$tmp_file"
            cat "$snippet_file" >> "$tmp_file"
            echo "" >> "$tmp_file"
            mv "$tmp_file" "$target_file"
            success "Updated snippet in $target_file"
        else
            info "Keeping existing snippet"
        fi
        return
    fi

    # Append snippet
    echo "" >> "$target_file"
    cat "$snippet_file" >> "$target_file"
    echo "" >> "$target_file"
    success "Injected comms snippet into $target_file"
}

AGENT_CHOICE=""
if [[ -n "$ARG_AGENT" ]]; then
    case "$ARG_AGENT" in
        claude) AGENT_CHOICE="1" ;;
        codex)  AGENT_CHOICE="2" ;;
        other)  AGENT_CHOICE="3" ;;
        skip)   AGENT_CHOICE="4" ;;
        *)      fatal "Invalid --agent: $ARG_AGENT (expected: claude, codex, other, skip)" ;;
    esac
    info "Agent: $ARG_AGENT (from --agent flag)"
else
    menu AGENT_CHOICE "Which agent do you use?" \
        "Claude Code" \
        "Codex" \
        "Other (specify rules file)" \
        "Skip"
fi

case "$AGENT_CHOICE" in
    1)
        # Claude Code integration
        info "Setting up Claude Code integration..."

        # Inject CLAUDE.md snippet
        CLAUDE_MD="$INSTALL_DIR/CLAUDE.md"
        inject_snippet "$CLAUDE_MD" "$SCRIPT_DIR/templates/CLAUDE.md.snippet"

        # Copy slash command
        COMMANDS_DIR="$INSTALL_DIR/.claude/commands"
        mkdir -p "$COMMANDS_DIR"
        if [[ -f "$COMMANDS_DIR/comms.md" ]]; then
            warn "Slash command already exists at $COMMANDS_DIR/comms.md"
            if confirm "Update slash command?"; then
                cp "$SCRIPT_DIR/commands/comms.md" "$COMMANDS_DIR/comms.md"
                success "Updated /comms slash command"
            fi
        else
            cp "$SCRIPT_DIR/commands/comms.md" "$COMMANDS_DIR/comms.md"
            success "Installed /comms slash command"
        fi

        # Install hooks if hooks dir exists or user confirms
        HOOKS_DIR="$INSTALL_DIR/.claude"
        if [[ -f "$HOOKS_DIR/hooks.json" ]]; then
            warn "hooks.json already exists — skipping hook installation"
            info "To add the inbox check hook manually, see: $SCRIPT_DIR/hooks/hooks.json"
        else
            if confirm "Install session-start inbox check hook?"; then
                cp "$SCRIPT_DIR/hooks/hooks.json" "$HOOKS_DIR/hooks.json"
                success "Installed hooks.json"
            fi
        fi

        success "Claude Code integration complete"
        ;;
    2)
        # Codex integration
        info "Setting up Codex integration..."

        AGENTS_MD="$INSTALL_DIR/AGENTS.md"
        inject_snippet "$AGENTS_MD" "$SCRIPT_DIR/templates/AGENTS.md.snippet"

        success "Codex integration complete"
        ;;
    3)
        # Other agent
        RULES_FILE=""
        ask RULES_FILE "Path to your agent's rules file" ""
        if [[ -z "$RULES_FILE" ]]; then
            warn "No rules file specified — skipping agent integration"
        else
            # Resolve relative path
            if [[ "$RULES_FILE" != /* ]]; then
                RULES_FILE="$(pwd)/$RULES_FILE"
            fi
            inject_snippet "$RULES_FILE" "$SCRIPT_DIR/templates/CLAUDE.md.snippet"
        fi
        ;;
    4)
        info "Skipping agent integration"
        ;;
esac

# ============================================================
# Step 6: Verify
# ============================================================

header "Step 6: Verify installation"

COMMS_CLI="$INSTALL_DIR/bin/comms"

# Run comms who
info "Running: comms who"
if "$COMMS_CLI" who 2>/dev/null; then
    success "Identity verified"
else
    warn "comms who failed — check comms.json configuration"
fi

echo ""

# Run comms peers
info "Running: comms peers"
if "$COMMS_CLI" peers 2>/dev/null; then
    success "Peer listing works"
else
    warn "comms peers failed — this is normal if you're the first instance"
fi

# Offer test if peers exist
if [[ ${#PEERS[@]} -gt 0 ]]; then
    echo ""
    if confirm "Send a test message to verify connectivity?"; then
        "$COMMS_CLI" test 2>/dev/null && success "Test message sent" || warn "Test failed"
    fi
fi

# ============================================================
# Step 7: Summary
# ============================================================

header "Installation complete!"

echo ""
printf "  ${BOLD}Instance:${RESET}    %s\n" "$INSTANCE_NAME"
printf "  ${BOLD}Hub:${RESET}         %s\n" "$(if [[ "$HUB_LOCAL" == "true" ]]; then echo "$HUB_PATH (local)"; else echo "$HUB_HOST:$HUB_PATH (remote)"; fi)"
printf "  ${BOLD}Peers:${RESET}       %s\n" "$(if [[ ${#PEERS[@]} -gt 0 ]]; then echo "${PEERS[*]}"; else echo "none yet"; fi)"
printf "  ${BOLD}CLI:${RESET}         %s\n" "$INSTALL_DIR/comms"
printf "  ${BOLD}Config:${RESET}      %s\n" "$CONFIG_FILE"

echo ""
printf "${DIM}Quick start:${RESET}\n"
echo "  ./comms check       # Check inbox"
echo "  ./comms peers       # List peers"
echo "  ./comms who         # Show identity"
echo "  ./comms send info \"Hello from $INSTANCE_NAME\"   # Send a message"
echo ""
printf "${DIM}To connect another instance, run install-comms.sh there and choose 'Join'.${RESET}\n"
echo ""
