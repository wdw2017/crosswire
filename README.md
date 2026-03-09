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

## Origin Story

This started with a Raspberry Pi. I was building a custom OpenWrt travel router image on my Mac Studio — it had all the source code, the cross-compilation toolchain, the build infrastructure. But the MacBook was the machine physically connected to the Pi via USB, responsible for flashing SD cards and debugging over serial.

Two Claude Code instances, two machines, one project. The Studio instance would build the image and tell the MacBook instance: *"Image ready. Pull it, flash the SD card, boot the Pi, and tell me what happens."* The MacBook instance would flash, test, and report back: *"DNS is broken — dnsmasq can't reach upstream."* The Studio instance would analyze its build config, find the root cause (nftables kill switch blocking port 53), push a fix, and send the next iteration.

What surprised me was how naturally they developed a **collective double-reasoning loop** — one agent with deep build context directing another with physical hardware access, each contributing what the other couldn't do alone. The conversation threading (`--re`) kept context tight across the back-and-forth, and because messages are plain text files, I could always `cat` them to see exactly what was being communicated.

I've since packaged it into a proper tool.

## What This Is

A dead-simple communication protocol for AI coding agents that works across any machines with SSH access. It's:

- **File-based** -- messages are plain text files. Debug with `cat`. No database, no daemon.
- **SSH-bridged** -- your laptop talks to your server's hub over SSH. No special ports, no VPN needed.
- **Agent-agnostic** -- works with Claude Code, Codex, Antigravity, or any agent that can run shell commands.
- **Token-efficient** -- ~20 token message headers. Your agent spends tokens on work, not protocol overhead.
- **Battle-tested** -- born from a real two-machine setup (MacBook + Mac Studio) that's been running for months.

## Demo

Two agents debugging a Raspberry Pi travel router — one builds, the other flashes and tests:

<p align="center">
  <img src="demo/demo.gif" alt="Demo: two Claude Code instances collaborating across machines" width="800">
</p>

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

## Why Would You Want This?

### The YOLO Sandbox
Your laptop instance is buttoned-up — no `sudo`, no `--force`, no `rm -rf` anything. But your server instance? Full permissions, YOLO mode, running in a throwaway VM you don't care about. You just say:

> *"Tell server to rebuild the Docker image from scratch, nuke the old volumes, and run the full integration suite"*

Your laptop agent sends the task, the server agent goes wild in its sandbox, and reports back when it's done. Mission control doesn't ride the rocket.

### The Overnight Forge
It's 11pm and you need to migrate a 200-table database, run the full test suite, and regenerate API docs. You tell your laptop agent:

> *"Ask server to run the database migration, execute the test suite, and regenerate the API docs. I'll check results in the morning."*

Close the laptop, go to bed. In the morning, your laptop instance checks the inbox: *"Migration complete. 847 tests passing. 3 deprecation warnings. Docs pushed to staging."* Coffee tastes better when the work's already done.

### The Split-Brain Monorepo
Frontend lives on your MacBook where you can eyeball it in a browser. Backend lives on your Linux server where Docker and Postgres actually run well. Two instances, each an expert in their half, passing API contract changes back and forth:

> *"Tell backend I added pagination to the user list — it needs a `cursor` param on `/api/users`"*

Your laptop agent sends the message, the server agent updates the endpoint, and replies with the new response schema. No context-switching, no "wait, which terminal was that in?"

### The CI Informant
Your CI pipeline spins up an agent that runs the test suite, and when something breaks, it doesn't just post a cryptic red badge — it sends your dev instance the full failure context, the relevant diff, and a suggested fix. You walk back to your desk and your agent says *"CI caught a null pointer in `OrderService.validate()`. I've got a patch ready. Want me to apply it?"*

### The Specialist Bench
One instance is your infrastructure brain — lives on the server, knows your cloud setup cold. Another is your code instance on your laptop. You say:

> *"Tell infra to provision a Redis instance for session caching and send back the connection string"*

Your laptop instance writes the application code while the infra instance runs Terraform, updates security groups, and replies with `redis://prod-cache.internal:6379`. Two experts, one conversation.

### The Paranoid Deployment
Your staging instance verifies the build, runs smoke tests, checks for environment drift. You tell your local agent:

> *"Ask staging to run the full verification suite, and only if it passes, tell prod to deploy v2.4.1"*

A chain of messages — staging reports "all clear," your agent forwards the deploy command to prod. No human fat-fingers the deploy. No single agent has both "test" and "deploy" permissions. Separation of concerns, enforced by physics.

### The GPU Loan Shark
You're iterating on a training script on your laptop, but training needs 80GB of VRAM on a server two rooms over. You say:

> *"Tell gpu-server to start training with the updated config in `experiments/v3.yaml` and report back every 100 epochs"*

You keep editing locally while the expensive hardware does the sweating. When training diverges, the server pings you immediately instead of burning tokens for three more hours.

### The Buddy System
Two devs on a team, each with their own Claude Code instance. Dev A's instance is refactoring auth; Dev B's is building a feature that depends on it. Instead of Slack messages and "hey, are you done yet?" — Dev A says:

> *"Tell bob that the auth refactor landed — `authenticate()` now returns `Result<Session>` instead of throwing"*

Bob's instance updates its code before the human even notices.

---

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

## Demo: Real Conversation

This is generated from the actual protocol (`bash demo/generate-demo.sh`). Two agents debugging a Raspberry Pi travel router across machines:

<details>
<summary><b>Click to expand full demo session</b></summary>

```
[studio] User: "tell laptop to pull the image and flash it"

[studio] $ comms send --to laptop task "OpenWrt image build complete.
  Pull via scp, flash to 32GB SD card, report when Pi boots."
→ Sent: f9931c0f

[laptop] $ comms check
f9931c0f  task  studio  OpenWrt image build complete.

[laptop] $ comms read f9931c0f
id: 20260309-011457-f9931c0f
from: studio
to: laptop
type: task
re:

OpenWrt image build complete.
Pull via: scp studio:travel-router/_build/openwrt-rpi5.img.gz .
Flash to 32GB SD card with:
  gunzip -k openwrt-rpi5.img.gz
  sudo dd if=openwrt-rpi5.img of=/dev/diskN bs=4M status=progress
Report back when the Pi boots and connects to WiFi.

[laptop] — Flashes SD card, boots Pi, tests connectivity...

[laptop] $ comms send reply --re f9931c0f "WiFi AP is up. DNS broken.
  Suspect nftables kill switch blocking port 53."
→ Sent: 8e75f5a7

[studio] $ comms read 8e75f5a7
id: 20260309-011457-8e75f5a7
from: laptop
to: studio
type: reply
re: f9931c0f

Image flashed and Pi booted.
WiFi AP is up (SSID: TravelRouter). Connected successfully.
BUT: DNS not resolving. curl google.com fails.
dnsmasq is running but upstream queries timeout.
Suspect the nftables kill switch is blocking port 53.

[studio] — Analyzes build config, finds root cause...

[studio] $ comms send reply --re 8e75f5a7 "Port 53 exemption missing.
  Add: nft add rule inet fw4 output udp dport 53 accept"
→ Sent: ae83f410

[laptop] — Applies fix on Pi, tests again...

[laptop] $ comms send reply --re ae83f410 "ALL WORKING!
  DNS resolves, VPN active, xray clean."
→ Sent: eae02edb

[studio] $ comms read eae02edb
id: 20260309-011457-eae02edb
from: laptop
to: studio
type: reply
re: ae83f410

ALL WORKING!
DNS: google.com resolves via 127.0.0.1 (dnsmasq)
VPN: curl ifconfig.me returns 203.0.113.42 (VPN server)
Xray log: clean, no errors
Travel router is fully operational.
```

4 messages. Bug found, diagnosed, fixed, verified. Two agents, two machines, one conversation thread.

</details>

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
