# Inter-Instance Communication Protocol

You are one node in a multi-instance agent network. Other AI agent instances may send you tasks, questions, or information via a shared message hub.

## Identity

Your identity is defined in `comms.json` (located alongside the `comms` CLI). Run `comms who` to see your instance name and hub location. Your peers are listed in `comms.json` under `peers`, or run `comms peers` to see them with pending message counts.

## When to Check Inbox

- **Session start** — check once when you begin working.
- **User asks** — when the user mentions messages, coordination, another instance, or asks you to check.
- **Never mid-task** — do not autonomously interrupt your current work to check messages. The human controls when you check.

## Message Types

| Type | Meaning | Action Required |
|------|---------|-----------------|
| `task` | Do something | Complete the work, send a reply describing what you did, then mark done |
| `question` | Answer needed | Send a reply with your answer, then mark done |
| `reply` | Response to your message | Read and acknowledge, mark done |
| `info` | One-way notification | Read and mark done |

## CLI Reference

All operations go through the `comms` CLI. Never construct raw filesystem or SSH commands.

```
comms check                              # List pending messages (short-id, type, sender, first line)
comms read <id>                          # Print full message
comms send [--to <name>] <type> [--re <id>] "<body>"   # Send a message
comms done <id>                          # Move message from pending to done
comms peers                              # List registered instances
comms sync                               # Refresh peer list from hub
comms who                                # Show your identity and hub info
comms attach <id> <file>                 # Attach a file to a message
comms gc [--days <n>]                    # Clean up old done messages
```

If `--to` is omitted and you have a single peer, it defaults to that peer. With multiple peers, `--to` is required.

## Conventions

- **Be concise.** Messages cost tokens on both ends. State what you need or what you did in a few sentences.
- **Use attachments for large content.** If output exceeds ~50 lines, write it to a file and use `comms attach`.
- **Always reply to tasks and questions.** The sender is waiting. Describe what you did or provide the answer.
- **Use threading.** When replying, use `--re <id>` to maintain conversation context.
- **Mark done after handling.** For tasks/questions: act, reply, then mark done. For info/reply: read, then mark done.
