# claude-instance-comms — Design Document

> Packageable, agent-agnostic multi-instance communication protocol for AI coding agents.
> Repo: `alexthec0d3r/claude-instance-comms` | License: AGPL-3.0

## Understanding Summary

1. **What**: A packageable, agent-agnostic multi-instance communication protocol based on a proven file-based system — directories as state machines, plain text messages, atomic writes
2. **Why**: No existing tool solves cross-machine AI agent coordination. Agent Teams, AMQ, etc. are all single-machine. This fills a real gap.
3. **Who**: Claude Code power users running multiple instances across machines (primary). Teams and CI/CD as stretch goals. Agent-agnostic — works with Codex, Antigravity, and others.
4. **Hub model**: Most accessible machine acts as hub (remote server, main workstation, anything with SSH access). Hub serves as both registry and message transport. All instances connect to it.
5. **Distribution**: Claude Code plugin first (`claude plugin add`), with `install-comms.sh` for configuration, manual setup, and non-Claude-Code agents
6. **Scale target**: 2-10 instances (file-based sweet spot)
7. **License**: AGPL-3.0
8. **Key differentiator**: Cross-machine coordination via SSH — the thing nobody else has packaged

## Assumptions

- Bash is the only hard dependency. JSON parsing uses `jq` if available, falls back to `python3 -c "import json; ..."` (both near-universal on macOS/Linux)
- SSH key-based auth is a prerequisite for remote instances (we don't solve SSH setup)
- The protocol format is plain text with a 5-line header (proven, token-efficient)
- Human controls when the agent checks inbox (no autonomous polling)
- MCP server layer is a future enhancement, not MVP — CLI-first

---

## Protocol

### Message Format

Plain text, fixed 5-line header, body after blank line:

```
id: YYYYMMDD-HHMMSS-XXXXXXXX
from: studio
to: local
type: task
re:

Your message body here.
```

- **id**: Timestamp + 8-hex-char random suffix (4 billion values, collision-safe for N instances). Also the filename (without `.msg`).
- **from**: Sender instance name
- **to**: Recipient instance name
- **type**: `task` (do something, reply expected), `question` (answer expected), `reply` (response to a prior message), `info` (one-way, no reply expected)
- **re**: ID of the parent message for threading. Empty if starting a new conversation.

Body is free-form text. Can contain code blocks, file references, etc.

### Hub Layout

```
.comms/
├── registry/
│   ├── studio.json            # One file per registered node
│   ├── local.json
│   └── ci-runner.json
├── to-studio/
│   ├── pending/               # Messages awaiting processing
│   └── done/                  # Processed messages
├── to-local/
│   ├── pending/
│   └── done/
├── tmp/                       # Staging area for atomic writes
└── files/                     # Attachments keyed by message ID
```

State is encoded in directory location: a message in `pending/` needs action; in `done/` it's been handled. No status fields to parse.

### Node Registry

Each registered node has a JSON file in `registry/`:

```json
{
  "name": "studio",
  "registered": "2026-03-09T14:30:00Z",
  "hubLocal": true
}
```

Remote node:

```json
{
  "name": "local",
  "registered": "2026-03-09T14:45:00Z",
  "hubLocal": false,
  "hubAccess": "ssh://palexey@macbook:/Users/palexey/projects/general"
}
```

The hub is the single source of truth for who exists. Nodes pull peer info on demand via `comms sync`.

### Node Config (`comms.json`)

Per-node config, stored alongside the `comms` CLI:

```json
{
  "self": "studio",
  "hub": {
    "path": "/Users/palexey-studio/projects/general/.comms",
    "host": null,
    "local": true
  },
  "peers": ["local", "ci-runner"],
  "defaultPeer": "local"
}
```

Remote node:

```json
{
  "self": "local",
  "hub": {
    "path": "/Users/palexey-studio/projects/general/.comms",
    "host": "palexey@mac-studio",
    "local": false
  },
  "peers": ["studio", "ci-runner"],
  "defaultPeer": "studio"
}
```

---

## Package Structure

```
claude-instance-comms/
├── .claude-plugin/
│   └── plugin.json                # Plugin manifest
├── commands/
│   └── comms.md                   # /comms slash command
├── skills/
│   └── comms/
│       └── SKILL.md               # Protocol knowledge for any agent
├── hooks/
│   └── hooks.json                 # Check inbox on session start
├── bin/
│   └── comms                      # The CLI (bash + jq)
├── install-comms.sh               # Standalone installer
├── templates/
│   ├── comms.json.template        # Node config template
│   ├── CLAUDE.md.snippet          # For CLAUDE.md injection
│   ├── AGENTS.md.snippet          # For Codex injection
│   └── PROTOCOL.md               # Human-readable protocol reference
├── lib/
│   └── transport.sh               # SSH transport shim (sourced by CLI)
├── LICENSE                        # AGPL-3.0
├── README.md
└── tests/
    └── test-comms.sh              # Self-test suite
```

---

## CLI Design

### Subcommands

```
comms init-hub [--path <dir>] [--remote user@host:<dir>]
    Create hub structure (registry/, tmp/, files/)
    Register self if --name provided

comms join --name <name> --hub <path|user@host:path>
    Register in hub registry
    Create own inbox (to-{name}/pending/, done/)
    Pull peers, write comms.json

comms sync
    Pull registry/*.json from hub
    Update local peers list in comms.json

comms check
    List pending inbox messages (short-id, type, sender, first line of body)

comms read <id>
    Print full message

comms send [--to <name>] <type> [--re <id>] <body>
    Write message to hub's to-{name}/pending/
    Falls back to defaultPeer if --to omitted and single peer
    Errors if --to omitted and multiple peers

comms done <id>
    Move from pending/ to done/

comms peers
    List registered nodes with pending message counts

comms who
    Print self identity + hub location

comms gc [--days <n>]
    Remove done/ messages older than n days (default 7)

comms attach <id> <file>
    Copy file to hub's files/{id}/

comms test [--to <name>]
    Send a ping, wait for pong (connectivity verification)
```

### Transport Layer

The CLI detects local vs remote hub from `comms.json` and delegates accordingly:

```bash
hub_run()   # execute arbitrary command (local shell or ssh)
hub_read()  # cat a file
hub_write() # write a file (stdin → file)
hub_mv()    # atomic move (state transitions)
hub_ls()    # list directory
```

All subcommands use these primitives — never raw filesystem calls. `hub_run` enables arbitrary remote operations (gc, registry queries, future subcommands) without adding new primitives. SSH transport works with zero changes to command logic.

### `comms check` Output Format (token-efficient)

```
a1b2  task     local      Deploy the frontend build
c3d4  question ci-runner  Which branch should I test?
```

Four columns: short ID suffix, type, sender, first line of body (truncated). One call gives the agent enough context to decide what to read.

### Error Messages

```
comms send --to nonexistent ...  → "Error: peer 'nonexistent' not found. Run: comms sync"
comms read nonexistent-id        → "Error: message not found"
comms send (no --to, 3 peers)    → "Error: multiple peers. Use --to <name>. Peers: alice, bob, carol"
comms join --name existing       → "Error: 'existing' already registered. Use a different name"
Hub unreachable via SSH           → "Error: cannot reach hub at user@host. Check SSH config"
jq not found                     → "Error: jq is required. Install: brew install jq (macOS) / apt install jq (Linux)"
```

---

## Agent Integration

### Rules File Injection

The installer injects a concise snippet into the agent's rules file (CLAUDE.md, AGENTS.md, or custom):

```markdown
<!-- claude-instance-comms:start -->
## Inter-Instance Communication

This project uses `claude-instance-comms` for cross-instance coordination.
- Your identity and peers are in `comms.json`
- Always use the `comms` CLI for all operations. Never construct raw commands.
- Check inbox: `comms check` — do this at session start
- Read: `comms read <id>`
- Send: `comms send [--to <name>] <type> [--re <id>] "body"`
- Mark done: `comms done <id>`
- List peers: `comms peers`
- Sync peer list: `comms sync`
<!-- claude-instance-comms:end -->
```

Properties:
- **Self-contained** — agent can operate with just this, no skill file needed
- **Token-lean** — ~100 tokens
- **Points to `comms.json`** — agent discovers identity at runtime
- **Markers** — enable idempotent update/removal on upgrades

### Slash Command (`/comms`)

Wraps CLI with natural language shortcuts:
- `/comms` or `/comms check` — check and summarize inbox
- `/comms ask [name] body` — send a question
- `/comms tell [name] body` — send info
- `/comms reply <id> body` — reply to a message
- `/comms peers` — list instances
- `/comms sync` — refresh peer list

### SKILL.md (Agent-Agnostic Knowledge)

Teaches any LLM agent the protocol:
- Identity discovery via `comms.json`
- When to check inbox (session start, user mentions coordination, never mid-task)
- Message types and conventions
- Conciseness rules and attachment usage

### Hooks

Optional session-start notification:
```json
{
  "hooks": [
    {
      "event": "Notification",
      "type": "command",
      "command": "comms check 2>/dev/null | head -5"
    }
  ]
}
```

---

## Installer Flow (`install-comms.sh`)

```
Step 1: Detect environment
  - Check for jq or python3 (one required for JSON parsing)
  - Check for ssh (optional, for remote hubs)
  - Check for SSH keys (~/.ssh/id_ed25519 or similar)
    - If missing, offer to generate: ssh-keygen -t ed25519
    - Optionally generate a dedicated comms-only key
    - Skip if keys already exist
  - Detect OS (macOS/Linux)

Step 2: Choose mode
  1) Create a new hub (this machine or remote)
  2) Join an existing hub

Step 3a: CREATE HUB
  - Hub directory path (default: ./.comms)
  - Local or remote (ssh user@host "mkdir -p ...")
  - Instance name (default: hostname-derived)
  - Register self in registry/

Step 3b: JOIN HUB
  - Hub location (local path or user@host:/path)
  - Test connectivity
  - Show existing peers
  - Instance name (validate unique)
  - Register + create inbox + pull peers

Step 4: Install CLI
  - Copy bin/comms to project root
  - Write comms.json
  - chmod +x

Step 5: Agent integration
  "Which agents do you use?"
  [ ] Claude Code (slash command + skill + hooks)
  [ ] Codex (AGENTS.md snippet)
  [ ] Other (specify rules file path)
  → Detect existing rules file
  → Check for existing snippet (idempotent)
  → Inject with markers

Step 6: Verify
  - comms who
  - comms peers
  - Offer comms test if peers exist

Step 7: Print summary
```

Properties: idempotent, no sudo, non-destructive, offline-capable.

---

## Test Suite (`tests/test-comms.sh`)

Creates a temporary hub with two fake nodes, verifies full lifecycle:

1. **Hub init** — verify directory structure
2. **Node join** — register alice + bob, verify registry + inbox dirs
3. **Peer sync** — alice sees bob, bob sees alice
4. **Send + receive** — alice sends task to bob, verify delivery
5. **Reply threading** — bob replies with re: chain intact
6. **Done lifecycle** — pending → done, verify moved
7. **Attachments** — send with file, verify in files/{id}/
8. **Garbage collection** — old done messages cleaned up
9. **Peers command** — correct counts displayed
10. **Edge cases** — no --to with multiple peers (error), duplicate join (error), empty inbox (clean output)

---

## Decision Log

| # | Decision | Alternatives Considered | Rationale |
|---|----------|------------------------|-----------|
| 1 | AGPL-3.0 license | BSL 1.1, ELv2, Apache+Commons Clause | OSI-approved open source, copyleft prevents commercial exploitation without contribution |
| 2 | File-based protocol, no database | SQLite, Redis, NATS | Zero dependencies, debuggable with Unix tools, proven in existing system |
| 3 | Hub-and-spoke topology | Peer-to-peer, mesh/rsync | Single source of truth, no consensus needed, maps to SSH access patterns |
| 4 | Hub as registry + transport | Config-only peers, mDNS discovery | Hub already exists as shared state; natural place for peer registry. Nodes sync on demand |
| 5 | JSON for config, plain text for messages | All JSON, all plain text, YAML | JSON is structured + language-agnostic for config. Plain text is token-efficient + human-debuggable for messages |
| 6 | Added `to:` header field | Implicit from directory path, separate routing file | Explicit addressing in the message — self-documenting, works for N instances |
| 7 | Plugin + standalone installer dual path | Plugin only, installer only, npm package | Plugin for Claude Code native UX, installer for Codex/Antigravity/manual. Same CLI core |
| 8 | Bash with jq/python3 JSON fallback | Python, Go binary (like AMQ), Node, INI config | Zero hard deps. jq preferred, python3 fallback for JSON parsing. Runs everywhere, no build step |
| 9 | Transport abstraction via hub_read/write/mv/ls | SSHFS mount requirement, MCP server | Keeps the CLI pure, SSH works without FUSE, can add transports later |
| 10 | Human controls inbox checking | Auto-poll, hooks-based interrupts | Matches agent UX principles — AI serves current user intent, doesn't self-interrupt |
| 11 | SKILL.md for agent-agnostic knowledge | CLAUDE.md only, MCP tool descriptions | Portable across any LLM agent. Teaches protocol without assuming Claude Code |
| 12 | `comms check` returns compact summary | Full message dump, IDs only | Token-efficient — one call gives enough context to decide without reading everything |
| 13 | Scope: 2-10 instances | Unlimited scale, exactly 2 | File-based protocol's sweet spot. Beyond 10, recommend a proper message broker |
| 14 | MCP server is future enhancement, not MVP | MCP-first (like mcp_agent_mail) | CLI-first is simpler, proven, agent-agnostic. MCP can layer on top later |
| 15 | Cross-machine via SSH as key differentiator | Local-only (like Agent Teams, AMQ) | Genuine gap in ecosystem — no existing tool packages cross-machine agent coordination |
| 16 | Inject concise comms snippet into agent rules file | Skill-only, full protocol in rules, manual setup | Rules file injection guarantees agent awareness every session. ~100 tokens. Markers enable idempotent update/removal |

---

## Competitive Landscape

| Tool | Scope | Transport | Cross-Machine | Agent-Agnostic |
|------|-------|-----------|---------------|----------------|
| **Agent Teams** (Anthropic) | Same machine | Local filesystem | No | No (Claude Code only) |
| **AMQ** | Same machine | Maildir files | No | Partial (skill-based) |
| **MCP Agent Mail** | Same machine | FastMCP + SQLite | No | Yes (MCP) |
| **Gastown** | Same machine | Go + tmux | No | No (Claude Code only) |
| **claude-instance-comms** | **Cross-machine** | **Filesystem + SSH** | **Yes** | **Yes** |

---

## Future Enhancements (Not MVP)

- MCP server wrapping the CLI (native tool integration)
- Broadcast channel (`to-all/`) with per-node read tracking
- Status/heartbeat files (`.comms/status/{name}.json`)
- Message priority levels
- Message TTL/expiry
- Web dashboard for hub monitoring
- SSHFS auto-mount configuration (launchd/systemd)
