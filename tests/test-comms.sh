#!/usr/bin/env bash
# test-comms.sh — Self-contained test suite for claude-instance-comms
# Creates a temporary hub with two fake nodes, verifies full lifecycle.
# Exit 0 if all pass, 1 if any fail.

set -uo pipefail

# --- Locate the real repo ---
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REAL_COMMS="$REPO_DIR/bin/comms"

if [[ ! -x "$REAL_COMMS" ]]; then
    echo "Error: $REAL_COMMS not found or not executable" >&2
    exit 1
fi

# --- Test harness ---
TESTS=0
PASSED=0
FAILED=0

pass() {
    ((TESTS++))
    ((PASSED++))
    echo "  PASS: $1"
}

fail() {
    ((TESTS++))
    ((FAILED++))
    echo "  FAIL: $1 — $2"
}

# --- Temp directory setup ---
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/comms-test.XXXXXX")"
HUB_DIR="$WORK_DIR/hub"
ALICE_DIR="$WORK_DIR/alice"
BOB_DIR="$WORK_DIR/bob"
CAROL_DIR="$WORK_DIR/carol"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# --- Node helpers ---
# Each node gets its own directory tree with symlinks to the real bin/comms and lib/.
# When bash runs $NODE_DIR/bin/comms, BASH_SOURCE[0] is the symlink path,
# so SCRIPT_DIR resolves to $NODE_DIR/bin and ROOT_DIR to $NODE_DIR.
# This means each node has its own comms.json at $NODE_DIR/comms.json.

setup_node_dir() {
    local node_dir="$1"
    mkdir -p "$node_dir/bin"
    ln -sf "$REPO_DIR/bin/comms" "$node_dir/bin/comms"
    ln -sf "$REPO_DIR/lib" "$node_dir/lib"
}

alice() { "$ALICE_DIR/bin/comms" "$@"; }
bob()   { "$BOB_DIR/bin/comms" "$@"; }
carol() { "$CAROL_DIR/bin/comms" "$@"; }

# --- Capture helpers ---
# Run a command and capture stdout+stderr, preserving exit code
run_capture() {
    local _rc=0
    OUTPUT="$("$@" 2>&1)" || _rc=$?
    return $_rc
}

# ============================================================
# TEST 1: Hub init
# ============================================================
echo ""
echo "=== Test 1: Hub init ==="

# Use alice's comms to init the hub (init-hub doesn't need comms.json)
setup_node_dir "$ALICE_DIR"
alice init-hub --path "$HUB_DIR" >/dev/null 2>&1

if [[ -d "$HUB_DIR/.comms/registry" ]]; then
    pass "registry/ exists"
else
    fail "registry/ exists" "directory not found"
fi

if [[ -d "$HUB_DIR/.comms/tmp" ]]; then
    pass "tmp/ exists"
else
    fail "tmp/ exists" "directory not found"
fi

if [[ -d "$HUB_DIR/.comms/files" ]]; then
    pass "files/ exists"
else
    fail "files/ exists" "directory not found"
fi

# ============================================================
# TEST 2: Node join
# ============================================================
echo ""
echo "=== Test 2: Node join ==="

HUB_PATH="$HUB_DIR/.comms"

alice join --name alice --hub "$HUB_PATH" >/dev/null 2>&1

if [[ -f "$HUB_PATH/registry/alice.json" ]]; then
    pass "alice registered in hub registry"
else
    fail "alice registered in hub registry" "registry/alice.json not found"
fi

if [[ -d "$HUB_PATH/to-alice/pending" ]]; then
    pass "alice pending inbox exists"
else
    fail "alice pending inbox exists" "to-alice/pending/ not found"
fi

if [[ -d "$HUB_PATH/to-alice/done" ]]; then
    pass "alice done dir exists"
else
    fail "alice done dir exists" "to-alice/done/ not found"
fi

# Join bob
setup_node_dir "$BOB_DIR"
bob join --name bob --hub "$HUB_PATH" >/dev/null 2>&1

if [[ -f "$HUB_PATH/registry/bob.json" ]]; then
    pass "bob registered in hub registry"
else
    fail "bob registered in hub registry" "registry/bob.json not found"
fi

if [[ -d "$HUB_PATH/to-bob/pending" && -d "$HUB_PATH/to-bob/done" ]]; then
    pass "bob inbox dirs exist"
else
    fail "bob inbox dirs exist" "to-bob/pending/ or to-bob/done/ not found"
fi

# Verify bob's comms.json has alice as peer
if [[ -f "$BOB_DIR/comms.json" ]]; then
    bob_peers="$(jq -r '.peers[]' "$BOB_DIR/comms.json" 2>/dev/null || true)"
    if echo "$bob_peers" | grep -q "alice"; then
        pass "bob's config lists alice as peer"
    else
        fail "bob's config lists alice as peer" "peers: $bob_peers"
    fi
else
    fail "bob's comms.json exists" "file not found"
fi

# ============================================================
# TEST 3: Peer sync
# ============================================================
echo ""
echo "=== Test 3: Peer sync ==="

# Alice joined before bob, so alice doesn't know about bob yet
alice sync >/dev/null 2>&1

alice_peers="$(jq -r '.peers[]' "$ALICE_DIR/comms.json" 2>/dev/null || true)"
if echo "$alice_peers" | grep -q "bob"; then
    pass "alice sees bob after sync"
else
    fail "alice sees bob after sync" "peers: $alice_peers"
fi

# Bob syncs too
bob sync >/dev/null 2>&1
bob_peers="$(jq -r '.peers[]' "$BOB_DIR/comms.json" 2>/dev/null || true)"
if echo "$bob_peers" | grep -q "alice"; then
    pass "bob sees alice after sync"
else
    fail "bob sees alice after sync" "peers: $bob_peers"
fi

# ============================================================
# TEST 4: Send + receive
# ============================================================
echo ""
echo "=== Test 4: Send + receive ==="

send_output="$(alice send --to bob task "hello world" 2>&1)"

# Extract the short ID from send output (format: "Sent task to bob [XXXXXXXX]")
ALICE_MSG_SHORT="$(echo "$send_output" | sed -n 's/.*\[\(.*\)\].*/\1/p')"

# Verify message file exists in bob's pending
pending_files="$(ls "$HUB_PATH/to-bob/pending/" 2>/dev/null)"
if [[ -n "$pending_files" ]]; then
    pass "message file exists in to-bob/pending/"
else
    fail "message file exists in to-bob/pending/" "directory empty"
fi

# Bob checks inbox
check_output="$(bob check 2>&1)"
if echo "$check_output" | grep -q "hello world"; then
    pass "bob check shows the message"
else
    fail "bob check shows the message" "output: $check_output"
fi

if echo "$check_output" | grep -q "task"; then
    pass "bob check shows message type"
else
    fail "bob check shows message type" "output: $check_output"
fi

if echo "$check_output" | grep -q "alice"; then
    pass "bob check shows sender"
else
    fail "bob check shows sender" "output: $check_output"
fi

# Bob reads the message
read_output="$(bob read "$ALICE_MSG_SHORT" 2>&1)"
if echo "$read_output" | grep -q "^from: alice$"; then
    pass "read shows from: alice"
else
    fail "read shows from: alice" "output: $read_output"
fi

if echo "$read_output" | grep -q "^to: bob$"; then
    pass "read shows to: bob"
else
    fail "read shows to: bob" "output: $read_output"
fi

if echo "$read_output" | grep -q "^type: task$"; then
    pass "read shows type: task"
else
    fail "read shows type: task" "output: $read_output"
fi

# Extract full message ID for threading test
ALICE_MSG_FULL="$(echo "$read_output" | sed -n 's/^id: *//p' | head -1)"

# ============================================================
# TEST 5: Reply threading
# ============================================================
echo ""
echo "=== Test 5: Reply threading ==="

reply_output="$(bob send --to alice reply --re "$ALICE_MSG_FULL" "got it" 2>&1)"
BOB_REPLY_SHORT="$(echo "$reply_output" | sed -n 's/.*\[\(.*\)\].*/\1/p')"

# Read the reply and verify re: field
reply_read="$(alice read "$BOB_REPLY_SHORT" 2>&1)"
reply_re="$(echo "$reply_read" | sed -n 's/^re: *//p' | head -1)"

if [[ "$reply_re" == "$ALICE_MSG_FULL" ]]; then
    pass "reply re: field matches original ID"
else
    fail "reply re: field matches original ID" "expected '$ALICE_MSG_FULL', got '$reply_re'"
fi

if echo "$reply_read" | grep -q "^type: reply$"; then
    pass "reply type is reply"
else
    fail "reply type is reply" "output: $reply_read"
fi

if echo "$reply_read" | grep -q "^from: bob$"; then
    pass "reply from: bob"
else
    fail "reply from: bob" "output: $reply_read"
fi

# Alice can read the reply body
if echo "$reply_read" | grep -q "got it"; then
    pass "alice can read reply body"
else
    fail "alice can read reply body" "output: $reply_read"
fi

# ============================================================
# TEST 6: Done lifecycle
# ============================================================
echo ""
echo "=== Test 6: Done lifecycle ==="

# Bob marks alice's original message as done
bob done "$ALICE_MSG_SHORT" >/dev/null 2>&1

# Verify moved from pending to done
pending_after="$(ls "$HUB_PATH/to-bob/pending/" 2>/dev/null | grep "$ALICE_MSG_SHORT" || true)"
if [[ -z "$pending_after" ]]; then
    pass "message removed from pending/"
else
    fail "message removed from pending/" "file still in pending"
fi

done_files="$(ls "$HUB_PATH/to-bob/done/" 2>/dev/null | grep "$ALICE_MSG_SHORT" || true)"
if [[ -n "$done_files" ]]; then
    pass "message moved to done/"
else
    fail "message moved to done/" "file not in done/"
fi

# check returns empty (only alice's reply should be in alice's inbox, not bob's)
bob_check="$(bob check 2>&1)"
if echo "$bob_check" | grep -q "No pending"; then
    pass "bob check shows empty after done"
else
    fail "bob check shows empty after done" "output: $bob_check"
fi

# read-done still works
done_read="$(bob read-done "$ALICE_MSG_SHORT" 2>&1)"
if echo "$done_read" | grep -q "hello world"; then
    pass "read-done retrieves processed message"
else
    fail "read-done retrieves processed message" "output: $done_read"
fi

# ============================================================
# TEST 7: Attachments
# ============================================================
echo ""
echo "=== Test 7: Attachments ==="

# Create a temp file to attach
ATTACH_FILE="$WORK_DIR/testfile.txt"
echo "attachment content here" > "$ATTACH_FILE"

# Alice attaches it to the original message she sent
alice attach "$ALICE_MSG_FULL" "$ATTACH_FILE" >/dev/null 2>&1

if [[ -d "$HUB_PATH/files/$ALICE_MSG_FULL" ]]; then
    pass "files/{msg-id}/ directory created"
else
    fail "files/{msg-id}/ directory created" "directory not found"
fi

if [[ -f "$HUB_PATH/files/$ALICE_MSG_FULL/testfile.txt" ]]; then
    pass "attachment file exists"
else
    fail "attachment file exists" "file not found"
fi

attach_content="$(cat "$HUB_PATH/files/$ALICE_MSG_FULL/testfile.txt")"
if [[ "$attach_content" == "attachment content here" ]]; then
    pass "attachment content matches"
else
    fail "attachment content matches" "content: $attach_content"
fi

# ============================================================
# TEST 8: Garbage collection
# ============================================================
echo ""
echo "=== Test 8: Garbage collection ==="

# Create a done message with an old timestamp (backdate it)
GC_MSG_ID="20240101-120000-deadbeef"
cat > "$HUB_PATH/to-bob/done/${GC_MSG_ID}.msg" <<EOF
id: ${GC_MSG_ID}
from: alice
to: bob
type: info
re:

old message for gc test
EOF

# Backdate the file to 10 days ago so -mtime +0 picks it up
touch -t 202401010000 "$HUB_PATH/to-bob/done/${GC_MSG_ID}.msg"

# Verify the file exists before gc
if [[ -f "$HUB_PATH/to-bob/done/${GC_MSG_ID}.msg" ]]; then
    pass "gc test message exists before gc"
else
    fail "gc test message exists before gc" "file not created"
fi

# Run gc with --days 0 (delete files older than 0 days, i.e. modified > 24h ago)
bob gc --days 0 >/dev/null 2>&1

if [[ ! -f "$HUB_PATH/to-bob/done/${GC_MSG_ID}.msg" ]]; then
    pass "gc deleted old message"
else
    fail "gc deleted old message" "file still exists"
fi

# Verify gc doesn't delete recent done messages (alice's msg was just moved to done)
recent_done="$(ls "$HUB_PATH/to-bob/done/" 2>/dev/null | grep "$ALICE_MSG_SHORT" || true)"
if [[ -n "$recent_done" ]]; then
    pass "gc preserves recent done messages"
else
    fail "gc preserves recent done messages" "recent message was deleted"
fi

# ============================================================
# TEST 9: Peers command
# ============================================================
echo ""
echo "=== Test 9: Peers command ==="

peers_output="$(alice peers 2>&1)"

if echo "$peers_output" | grep -q "bob"; then
    pass "peers lists bob"
else
    fail "peers lists bob" "output: $peers_output"
fi

# alice's inbox still has bob's reply, so alice should see herself? No — peers shows OTHER peers
# and their pending counts. Let's check bob has no pending (we moved alice's msg to done).
# bob's inbox is empty, so count should be 0
if echo "$peers_output" | grep "bob" | grep -q "0"; then
    pass "peers shows correct pending count for bob"
else
    fail "peers shows correct pending count for bob" "output: $peers_output"
fi

# ============================================================
# TEST 10: Who command
# ============================================================
echo ""
echo "=== Test 10: Who command ==="

who_output="$(alice who 2>&1)"

if echo "$who_output" | grep -q "alice"; then
    pass "who shows identity alice"
else
    fail "who shows identity alice" "output: $who_output"
fi

if echo "$who_output" | grep -q "local"; then
    pass "who shows hub is local"
else
    fail "who shows hub is local" "output: $who_output"
fi

bob_who="$(bob who 2>&1)"
if echo "$bob_who" | grep -q "bob"; then
    pass "who shows identity bob"
else
    fail "who shows identity bob" "output: $bob_who"
fi

# ============================================================
# TEST 11: Edge cases
# ============================================================
echo ""
echo "=== Test 11: Edge cases ==="

# --- 11a: Send with no --to and multiple peers -> error ---
# Add carol so alice has multiple peers (alice, bob, carol)
setup_node_dir "$CAROL_DIR"
carol join --name carol --hub "$HUB_PATH" >/dev/null 2>&1
alice sync >/dev/null 2>&1

# Remove defaultPeer from alice's config so the ambiguity triggers
if command -v jq &>/dev/null; then
    jq '.defaultPeer = null' "$ALICE_DIR/comms.json" > "$ALICE_DIR/comms.json.tmp" && \
        mv "$ALICE_DIR/comms.json.tmp" "$ALICE_DIR/comms.json"
fi

run_capture alice send task "no recipient specified"
rc=$?
if [[ $rc -ne 0 ]]; then
    pass "send with no --to and multiple peers returns error"
else
    fail "send with no --to and multiple peers returns error" "exit code was $rc, output: $OUTPUT"
fi

if echo "$OUTPUT" | grep -qi "multiple\|peers\|--to"; then
    pass "error message mentions multiple peers or --to"
else
    fail "error message mentions multiple peers or --to" "output: $OUTPUT"
fi

# --- 11b: Send with no --to and single peer -> success ---
# Create a fresh node "dave" with only one peer
DAVE_DIR="$WORK_DIR/dave"
setup_node_dir "$DAVE_DIR"

# First register dave (after only alice exists, before others)
# Actually we need a clean scenario. Let's create a new hub for this test.
SINGLE_HUB="$WORK_DIR/single-hub"
mkdir -p "$SINGLE_HUB/.comms"/{registry,tmp,files}

# Create alice2 and dave in this isolated hub
ALICE2_DIR="$WORK_DIR/alice2"
setup_node_dir "$ALICE2_DIR"
"$ALICE2_DIR/bin/comms" join --name alice2 --hub "$SINGLE_HUB/.comms" >/dev/null 2>&1

setup_node_dir "$DAVE_DIR"
"$DAVE_DIR/bin/comms" join --name dave --hub "$SINGLE_HUB/.comms" >/dev/null 2>&1

# dave has exactly one peer (alice2), so send without --to should work
run_capture "$DAVE_DIR/bin/comms" send task "auto-routed message"
rc=$?
if [[ $rc -eq 0 ]]; then
    pass "send with no --to and single peer succeeds"
else
    fail "send with no --to and single peer succeeds" "exit code $rc, output: $OUTPUT"
fi

# --- 11c: Join with duplicate name -> error ---
run_capture bob join --name bob --hub "$HUB_PATH"
rc=$?
if [[ $rc -ne 0 ]]; then
    pass "duplicate join returns error"
else
    fail "duplicate join returns error" "exit code was $rc"
fi

if echo "$OUTPUT" | grep -qi "already registered"; then
    pass "duplicate join error mentions already registered"
else
    fail "duplicate join error mentions already registered" "output: $OUTPUT"
fi

# --- 11d: Check on empty inbox -> clean exit ---
# carol has no messages
run_capture carol check
rc=$?
if [[ $rc -eq 0 ]]; then
    pass "check on empty inbox exits 0"
else
    fail "check on empty inbox exits 0" "exit code was $rc"
fi

if echo "$OUTPUT" | grep -q "No pending"; then
    pass "empty inbox shows clean message"
else
    fail "empty inbox shows clean message" "output: $OUTPUT"
fi

# --- 11e: Read nonexistent message -> error ---
run_capture bob read "nonexistent-id-00000000"
rc=$?
if [[ $rc -ne 0 ]]; then
    pass "read nonexistent message returns error"
else
    fail "read nonexistent message returns error" "exit code was $rc"
fi

if echo "$OUTPUT" | grep -qi "not found"; then
    pass "read nonexistent error says not found"
else
    fail "read nonexistent error says not found" "output: $OUTPUT"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "==========================================="
echo "  Results: $PASSED passed, $FAILED failed (out of $TESTS)"
echo "==========================================="

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
else
    exit 0
fi
