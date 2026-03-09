# claude-instance-comms

> Your AI agents are lonely. Let them talk to each other.

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Agent: Agnostic](https://img.shields.io/badge/Agent-Agnostic-orange.svg)](#agent-integration)
[![Tests: 46/46](https://img.shields.io/badge/Tests-46%2F46-brightgreen.svg)](tests/test-comms.sh)

---

## The Problem

You're running Claude Code on your laptop. Another instance is humming away on your home server. A third one just spun up in CI. They're all working on the same project, but they might as well be on different planets.

**"Hey server-Claude, did you finish that API refactor?"** -- You can't ask that. There's no way for your agents to talk to each other across machines.

Existing tools solve this for agents on the *same* machine:
- **Agent Teams** (Anthropic) -- local filesystem only
- **AMQ** -- Maildir-style, single machine
- **MCP Agent Mail** -- FastMCP + SQLite, single machine

Nobody has packaged the **cross-machine** case. Until now.

## What This Is

A dead-simple communication protocol for AI coding agents that works across any machines with SSH access. It's:

- **File-based** -- messages are plain text files. Debug with `cat`. No database, no daemon.
- **SSH-bridged** -- your laptop talks to your server's hub over SSH. No special ports, no VPN needed.
- **Agent-agnostic** -- works with Claude Code, Codex, Antigravity, or any agent that can run shell commands.
- **Token-efficient** -- ~20 token message headers. Your agent spends tokens on work, not protocol overhead.
- **Battle-tested** -- born from a real two-machine setup (MacBook + Mac Studio) that's been running for months.

## How It Works

```
                        +-----------+
                        |    HUB    |
                        |  .comms/  |
                        |           |
              SSH       | registry/ |       Local
         +----------->  | to-alice/ |  <-----------+
         |              | to-bob/   |              |
         |              | to-ci/    |              |
         |              +-----------+              |
         |                                         |
    +---------+                              +---------+
    |  alice  |                              |   bob   |
    | laptop  |                              | server  |
    +---------+                              +---------+
         ^
         |  SSH
         |
    +---------+
    |   ci    |
    | runner  |
    +---------+
```

Pick your most accessible machine as the **hub**. It holds a `.comms/` directory -- that's it. Just folders and files. Every agent gets an inbox (`to-{name}/pending/`), and messages move to `done/` when handled. Atomic `mv` for state transitions. The Unix filesystem *is* the message queue.

Nodes talk to the hub over SSH (or locally if they're on the same machine). That's the entire transport layer.

## Quick Start

### Option 1: Claude Code Plugin

```bash
claude plugin add github:alexthec0d3r/claude-instance-comms
```

Then set up the hub and join:

```bash
# On the hub machine
comms init-hub --path .comms
comms join --name studio --hub .comms

# On a remote machine
comms join --name laptop --hub user@hub-host:/path/to/.comms
```

### Option 2: Standalone Installer

```bash
# Download first, inspect, then run
curl -fsSLO https://raw.githubusercontent.com/alexthec0d3r/claude-instance-comms/main/install-comms.sh
bash install-comms.sh
```

The installer walks you through everything: hub or join, instance name, SSH keys, agent integration. Two minutes, tops.

### Send Your First Message

```bash
# From your laptop
comms send --to studio task "Run the test suite and tell me what fails"

# On the server, your agent checks inbox
comms check
#=> a1b2c3d4  task  laptop  Run the test suite and tell me what fails

comms read a1b2c3d4
comms send reply --re a1b2c3d4 "All 46 tests pass. Ship it."
comms done a1b2c3d4
```

That's it. Plain text messages, directory-based state machine, zero magic.

## Message Format

Messages are human-readable. Open them with `cat` if you want -- no binary format, no serialization.

```
id: 20260309-143000-a1b2c3d4
from: laptop
to: studio
type: task
re:

Deploy the frontend build to staging and report back.
```

Four types:

| Type       | What it means               | Reply expected? |
|------------|-----------------------------|:---------------:|
| `task`     | Do something and report back | Yes            |
| `question` | I need information           | Yes            |
| `reply`    | Here's my response           | Maybe          |
| `info`     | FYI, no action needed        | No             |

## CLI Reference

```
comms init-hub [--path <dir>]                   Create hub directory structure
comms join --name <name> --hub <path>           Register as a node
comms sync                                      Refresh peer list from hub
comms check                                     List pending inbox messages
comms read <id>                                 Read a message
comms send [--to <name>] <type> [--re <id>] "body"
                                                Send a message
comms done <id>                                 Mark as processed
comms peers                                     List registered nodes
comms who                                       Print identity and hub info
comms gc [--days <n>]                           Clean old done/ messages
comms attach <id> <file>                        Attach a file to a message
comms test [--to <name>]                        Verify connectivity
```

## Agent Integration

The installer injects a concise snippet (~100 tokens) into your agent's rules file:

**Claude Code** -- CLAUDE.md + `/comms` slash command + session-start hooks
**Codex** -- AGENTS.md snippet
**Others** -- any rules file you point it to

The snippet is self-contained. Your agent knows the full CLI from just these lines:

```markdown
<!-- claude-instance-comms:start -->
## Inter-Instance Communication
This project uses `claude-instance-comms` for cross-instance coordination.
- Your identity and peers are in `comms.json`
- Check inbox: `comms check` -- do this at session start
- Send: `comms send [--to <name>] <type> [--re <id>] "body"`
...
<!-- claude-instance-comms:end -->
```

## Configuration

Each node has a `comms.json`:

```json
{
  "self": "laptop",
  "hub": {
    "path": "/home/user/project/.comms",
    "host": "user@studio-host",
    "local": false
  },
  "peers": ["studio", "ci-runner"],
  "defaultPeer": "studio"
}
```

If you only have one peer, `--to` is optional -- the CLI figures it out.

## Why Not Just Use X?

| Tool | Cross-Machine | Agent-Agnostic | Dependencies |
|------|:-------------:|:--------------:|:------------:|
| Agent Teams (Anthropic) | No | No | Claude Code |
| AMQ | No | Partial | Go binary |
| MCP Agent Mail | No | Yes | Python + SQLite |
| Gastown | No | No | Go + tmux |
| **claude-instance-comms** | **Yes** | **Yes** | **Bash + SSH** |

Every other tool assumes your agents live on the same machine. If they do, use Agent Teams -- it's great. But the moment you have a laptop *and* a server *and* a CI runner, you need something that bridges machines. That's us.

## Design Philosophy

- **Files are the API.** Messages are plain text. Directories are queues. `mv` is a state transition. If it works with `cat` and `ls`, it works with this tool.
- **SSH is the network.** You already have SSH keys. You already have access. We don't need another port, protocol, or certificate.
- **The human decides.** Your agent checks inbox when *you* tell it to. No autonomous polling, no mid-task interruptions. The human stays in control.
- **Zero hard dependencies.** Bash is the only requirement. jq is nice to have; python3 works as a fallback. That's it.

## License

[AGPL-3.0](LICENSE) -- Copyright (C) 2026 alexthec0d3r

Free software with teeth. Use it, modify it, share it -- but if you build on it, your work stays open too.

## Contributing

PRs welcome. Run the tests first:

```bash
bash tests/test-comms.sh
```

Interesting areas to explore:
- **MCP server wrapper** -- expose the CLI as native MCP tools
- **Broadcast channels** -- `to-all/` with per-node read tracking
- **Transport plugins** -- SSHFS, cloud storage, HTTP relay
- **Node heartbeats** -- liveness detection
- **Web dashboard** -- hub monitoring

Keep it simple. The protocol works because it's just files and directories. Let's keep it that way.
