# /comms — Inter-Instance Communication

Handle cross-instance messaging via the `comms` CLI. Parse `$ARGUMENTS` and run the appropriate subcommand.

## Rules

- **Always use the `comms` CLI.** Never construct raw bash commands for comms operations.
- Process task and question messages fully before marking them done — act on the request, send a reply, then mark done.
- Keep messages concise. Use `comms attach` for content over 50 lines.
- When replying, reference what you did, not just "done."

## Argument Handling

Based on `$ARGUMENTS`:

### No args or "check"
Run `comms check`. Summarize pending messages in a readable format — show count, senders, types, and first lines. Ask the user which message(s) to handle.

### "read <id>"
Run `comms read <id>`. Display the full message. If it's a task or question, offer to act on it.

### "send <type> [--to <name>] <body>"
Run `comms send [--to <name>] <type> "<body>"`. Confirm delivery. If `--to` is omitted and there's a single peer, the CLI uses `defaultPeer` automatically.

### "ask [<name>] <body>"
Shorthand for sending a question. Run `comms send [--to <name>] question "<body>"`.

### "tell [<name>] <body>"
Shorthand for sending info. Run `comms send [--to <name>] info "<body>"`.

### "reply <id> <body>"
Run `comms send reply --re <id> "<body>"`. Uses the original message's `from` field as the recipient.

### "done <id>"
Run `comms done <id>`. Only do this after you've fully handled the message — if it was a task or question, you must have already sent a reply.

### "peers"
Run `comms peers`. Display registered instances and their pending message counts.

### "sync"
Run `comms sync`. Refresh the local peer list from the hub registry.

### "init-hub [--remote user@host:/path]"
Run `comms init-hub` with any provided flags. Creates a new hub structure.

### "join --name <n> --hub <path>"
Run `comms join --name <name> --hub <path>`. Registers this instance with an existing hub.

### "who"
Run `comms who`. Display this instance's identity and hub location.

### Unrecognized arguments
Tell the user the command wasn't recognized and show available subcommands: check, read, send, ask, tell, reply, done, peers, sync, init-hub, join, who.
