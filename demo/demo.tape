# claude-instance-comms demo
# Two AI agents debugging a Raspberry Pi travel router across machines
# https://github.com/charmbracelet/vhs

Output demo/demo.gif
Output demo/demo.webm

Set Shell "bash"
Set FontSize 14
Set Width 960
Set Height 520
Set Theme "Catppuccin Mocha"
Set TypingSpeed 25ms
Set Padding 15

# ── Scene 1: User tells studio to send task to laptop ──
Type `# You're on the Mac Studio. The OpenWrt image just finished building.`
Enter
Type `# The MacBook is physically connected to the Raspberry Pi.`
Enter
Sleep 1.5s
Enter
Type `# You tell your Claude Code instance:`
Enter
Type `#   "tell laptop to pull the image, flash the SD card, and report back"`
Enter
Sleep 2s
Enter
Type `# Claude runs:`
Enter
Sleep 500ms

Type@50ms `comms send --to laptop task "OpenWrt image ready. Pull via scp, flash the 32GB SD card, boot the Pi, and tell me what happens."`
Enter
Sleep 1.5s
Type `# → Sent: f9931c0f`
Enter
Sleep 2s
Type "clear"
Enter
Sleep 400ms

# ── Scene 2: Laptop agent picks it up ──
Type `# Meanwhile on the MacBook, the laptop agent checks its inbox:`
Enter
Sleep 1s

Type `comms check`
Enter
Sleep 800ms
Type `# f9931c0f  task  studio  OpenWrt image ready. Pull via scp, flash...`
Enter
Sleep 1.5s

Type `comms read f9931c0f`
Enter
Sleep 600ms
Type `# id: 20260309-143000-f9931c0f`
Enter
Type `# from: studio  →  to: laptop  →  type: task`
Enter
Type `#`
Enter
Type `# OpenWrt image ready. Pull via scp, flash the 32GB`
Enter
Type `# SD card, boot the Pi, and tell me what happens.`
Enter
Sleep 2s
Type "clear"
Enter
Sleep 400ms

# ── Scene 3: Laptop flashes, finds DNS bug ──
Type `# The laptop agent flashes the SD card, boots the Pi...`
Enter
Type `# WiFi works! But DNS is broken.`
Enter
Sleep 1.5s
Enter
Type `# It reports back automatically:`
Enter
Sleep 500ms

Type@50ms `comms send reply --re f9931c0f "Pi booted, WiFi AP is up. BUT: DNS is broken. dnsmasq can't reach upstream. I think the nftables kill switch is blocking port 53."`
Enter
Sleep 1.5s
Type `# → Sent: 8e75f5a7`
Enter
Sleep 2s
Type "clear"
Enter
Sleep 400ms

# ── Scene 4: Studio diagnoses and sends fix ──
Type `# Back on the Studio, the agent reads the report.`
Enter
Type `# It digs through the build config and finds the root cause.`
Enter
Sleep 2s
Enter
Type `# You say: "tell laptop to apply the nftables fix"`
Enter
Sleep 1s

Type@50ms `comms send reply --re 8e75f5a7 "Found it — port 53 not exempted in nftables output chain. Apply: nft add rule inet fw4 output udp dport 53 accept"`
Enter
Sleep 1.5s
Type `# → Sent: ae83f410`
Enter
Sleep 2s
Type "clear"
Enter
Sleep 400ms

# ── Scene 5: Fixed! ──
Type `# The laptop agent applies the fix on the Pi and tests again.`
Enter
Sleep 1.5s

Type@50ms `comms send reply --re ae83f410 "ALL WORKING. DNS resolves, VPN active, xray clean. Travel router fully operational."`
Enter
Sleep 1.5s
Type `# → Sent: eae02edb`
Enter
Sleep 2.5s
Type "clear"
Enter
Sleep 400ms

# ── Summary ──
Type `# ✓ 4 messages. Bug found, diagnosed, fixed, verified.`
Enter
Type `# ✓ Two agents, two machines, one conversation thread.`
Enter
Type `# ✓ Plain text files over SSH. That's the whole protocol.`
Enter
Sleep 4s
