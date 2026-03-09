# claude-instance-comms Protocol Reference

Version 1.0

## Overview

claude-instance-comms uses a file-based protocol where directories encode state, plain text carries messages, and SSH bridges machines. A central **hub** acts as both registry and message transport. **Nodes** (agent instances) connect to the hub to send and receive messages.

---

## Message Format

Every message is a plain text file with a fixed 5-line header followed by a blank line and the message body.

```
id: YYYYMMDD-HHMMSS-XXXXXXXX
from: <sender>
to: <recipient>
type: <message-type>
re: <parent-id or empty>

Message body here. Free-form text.
Can contain code blocks, file references, etc.
```

### Header Fields

| Field  | Description |
|--------|-------------|
| `id`   | Timestamp (`YYYYMMDD-HHMMSS`) + 8 hex random chars. Unique across all nodes. Also the filename (without `.msg`). |
| `from` | Sender's instance name. |
| `to`   | Recipient's instance name. |
| `type` | One of: `task`, `question`, `reply`, `info`. |
| `re`   | ID of the parent message for threading. Empty string if starting a new conversation. |

### Message Types

| Type       | Meaning                          | Reply Expected |
|------------|----------------------------------|:--------------:|
| `task`     | Do something                     | Yes            |
| `question` | Answer a question                | Yes            |
| `reply`    | Response to a prior message      | Maybe          |
| `info`     | One-way informational message    | No             |

### Filename Convention

Messages are stored as `{id}.msg` where `{id}` matches the `id:` header value.

Example: `20260309-143000-a1b2c3d4.msg`

---

## Hub Layout

The hub is a directory tree that serves as the single source of truth.

```
.comms/
├── registry/
│   ├── alice.json              # One file per registered node
│   ├── bob.json
│   └── ci-runner.json
├── to-alice/
│   ├── pending/                # Messages awaiting processing
│   └── done/                   # Processed messages
├── to-bob/
│   ├── pending/
│   └── done/
├── tmp/                        # Staging area for atomic writes
└── files/                      # Attachments keyed by message ID
    └── 20260309-143000-a1b2c3d4/
        └── report.csv
```

### State Machine

State is encoded entirely by directory location:

- **`to-{name}/pending/{id}.msg`** -- Message needs action
- **`to-{name}/done/{id}.msg`** -- Message has been handled

There are no status fields, databases, or lock files. A single `mv` operation transitions state atomically.

### Staging (Atomic Writes)

To prevent partial reads, messages are written to `tmp/` first, then moved to the recipient's `pending/` directory. The `mv` operation is atomic on all POSIX filesystems.

```
1. Write message to   .comms/tmp/{id}.msg
2. Move message to    .comms/to-{recipient}/pending/{id}.msg
```

---

## Node Registry

Each registered node has a JSON file in `registry/`.

### Local Node (hub is on this machine)

```json
{
  "name": "alice",
  "registered": "2026-03-09T14:30:00Z",
  "hubLocal": true
}
```

### Remote Node (hub is on another machine)

```json
{
  "name": "bob",
  "registered": "2026-03-09T14:45:00Z",
  "hubLocal": false,
  "hubAccess": "ssh://user@hostname:/path/to/project"
}
```

The hub is the authoritative registry. Nodes pull peer information on demand via `comms sync`.

---

## Operations

### Send

1. Construct the message with a generated ID and 5-line header.
2. Write to `tmp/{id}.msg` on the hub (via local filesystem or SSH).
3. Move to `to-{recipient}/pending/{id}.msg`.

### Receive (Check Inbox)

1. List files in `to-{self}/pending/`.
2. For each file, read the header to extract short ID, type, sender, and first line of body.
3. Present as a compact summary.

### Read

1. Read the full contents of `to-{self}/pending/{id}.msg` (matching on the ID suffix is acceptable).

### Done

1. Move the message from `to-{self}/pending/{id}.msg` to `to-{self}/done/{id}.msg`.

### Sync

1. Read all files in `registry/` from the hub.
2. Update the local `comms.json` peer list.

### Garbage Collection

1. List files in `to-{self}/done/` (and optionally all `done/` directories on the hub).
2. Remove messages older than a threshold (default: 7 days), determined by the timestamp in the ID.

---

## Threading Model

Conversations are threaded via the `re:` header field.

```
Message A (re: "")            -- New conversation
  └── Message B (re: A.id)    -- Reply to A
       └── Message C (re: B.id)  -- Reply to B
```

Threads are linear chains. The `re:` field always references the immediate parent message, not the root. Agents can reconstruct the full thread by following the chain.

---

## Attachment System

Binary files and large content are stored separately from messages.

### Sending an Attachment

1. Create directory `files/{message-id}/` on the hub.
2. Copy the file into that directory.
3. Reference the attachment in the message body (by name).

### Structure

```
.comms/files/
└── 20260309-143000-a1b2c3d4/
    ├── screenshot.png
    └── debug.log
```

Attachments are keyed by the message ID they belong to. Multiple files can be attached to a single message.

---

## Transport

All hub operations use a transport abstraction layer with 5 primitives:

| Primitive    | Purpose                        |
|-------------|--------------------------------|
| `hub_run`   | Execute a command on the hub   |
| `hub_read`  | Read a file from the hub       |
| `hub_write` | Write a file to the hub        |
| `hub_mv`    | Move a file on the hub (atomic state transition) |
| `hub_ls`    | List a directory on the hub    |

For local hubs, these map to direct filesystem operations. For remote hubs, they map to SSH commands. This abstraction allows command logic to remain transport-agnostic.

---

## Conventions and Best Practices

### For AI Agents

1. **Check inbox at session start**, not during focused work. The human controls when coordination happens.
2. **Be concise.** Messages are read by other AI agents. Omit pleasantries. Lead with the actionable content.
3. **Use attachments for large content.** Keep message bodies under ~500 tokens. Use `comms attach` for logs, diffs, and data files.
4. **Always mark messages done** after processing them, even if no reply is needed. This keeps the inbox clean.
5. **Use the right message type.** `task` and `question` signal that a reply is expected. `info` signals fire-and-forget.
6. **Thread replies.** Always use `--re <id>` when responding to a message.

### For Operators

1. **One hub per project.** Place the `.comms/` directory in the shared project root.
2. **Use descriptive instance names.** `studio`, `laptop`, `ci-runner` -- not `node1`, `node2`.
3. **SSH keys are a prerequisite.** The protocol does not manage SSH authentication. Use `ssh-agent` and key-based auth.
4. **Scale target: 2-10 instances.** The file-based protocol works well in this range. Beyond 10, consider a message broker.
5. **Run `comms gc` periodically** to prevent unbounded growth of `done/` directories.
