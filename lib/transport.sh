#!/usr/bin/env bash
# transport.sh — Hub transport abstraction layer
# Sourced by bin/comms. Provides 5 primitives that work locally or via SSH.
# Requires HUB_PATH and optionally HUB_HOST to be set before use.

# IMPORTANT: callers must validate user-supplied inputs before passing to hub_run.
# Never pass untrusted input without sanitization.
hub_run() {
    if [[ "$HUB_LOCAL" == "true" ]]; then
        eval "$@"
    else
        ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" "$@" 2>/dev/null || {
            echo "Error: cannot reach hub at $HUB_HOST. Check SSH config" >&2
            return 1
        }
    fi
}

hub_read() {
    local path="$1"
    if [[ "$HUB_LOCAL" == "true" ]]; then
        cat "$HUB_PATH/$path"
    else
        ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" "cat '$HUB_PATH/$path'" 2>/dev/null || {
            echo "Error: cannot reach hub at $HUB_HOST. Check SSH config" >&2
            return 1
        }
    fi
}

hub_write() {
    local path="$1"
    if [[ "$HUB_LOCAL" == "true" ]]; then
        cat > "$HUB_PATH/$path"
    else
        ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" "cat > '$HUB_PATH/$path'" 2>/dev/null || {
            echo "Error: cannot reach hub at $HUB_HOST. Check SSH config" >&2
            return 1
        }
    fi
}

hub_mv() {
    local src="$1" dst="$2"
    if [[ "$HUB_LOCAL" == "true" ]]; then
        mv "$HUB_PATH/$src" "$HUB_PATH/$dst"
    else
        ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" "mv '$HUB_PATH/$src' '$HUB_PATH/$dst'" 2>/dev/null || {
            echo "Error: cannot reach hub at $HUB_HOST. Check SSH config" >&2
            return 1
        }
    fi
}

hub_ls() {
    local path="$1"
    if [[ "$HUB_LOCAL" == "true" ]]; then
        ls "$HUB_PATH/$path" 2>/dev/null
    else
        ssh -o ConnectTimeout=5 -o BatchMode=yes "$HUB_HOST" "ls '$HUB_PATH/$path'" 2>/dev/null || true
    fi
}
