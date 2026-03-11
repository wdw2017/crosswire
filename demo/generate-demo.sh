#!/usr/bin/env bash
# Generates a realistic demo session showing two agents collaborating
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Setup — mirror the test suite's proven pattern
setup_node() {
    local dir="$1"
    mkdir -p "$dir/bin" "$dir/lib"
    ln -sf "$REPO_DIR/bin/xw" "$dir/bin/xw"
    ln -sf "$REPO_DIR/lib/transport.sh" "$dir/lib/transport.sh"
}

HUB_PARENT="$WORK_DIR/hub"
HUB="$HUB_PARENT/.crosswire"
STUDIO_DIR="$WORK_DIR/studio"
LAPTOP_DIR="$WORK_DIR/laptop"

setup_node "$STUDIO_DIR"
setup_node "$LAPTOP_DIR"

studio() { "$STUDIO_DIR/bin/xw" "$@"; }
laptop() { "$LAPTOP_DIR/bin/xw" "$@"; }

# Initialize hub (init-hub appends .crosswire, so pass parent)
mkdir -p "$HUB_PARENT"
studio init-hub --path "$HUB_PARENT" > /dev/null 2>&1
# Join uses the actual .crosswire path directly
studio join --name studio --hub "$HUB" > /dev/null 2>&1
laptop join --name laptop --hub "$HUB" > /dev/null 2>&1
studio sync > /dev/null 2>&1

# ============================================================
# Generate plain-text demo (no ANSI — for README / conversion)
# ============================================================

cat << 'HEADER'
════════════════════════════════════════════════════════════════
  crosswire — Demo Session
════════════════════════════════════════════════════════════════

  Two Claude Code instances:
  • "studio" — Mac Studio (build server, has all source code)
  • "laptop" — MacBook Pro (connected to Raspberry Pi via USB)

────────────────────────────────────────────────────────────────
HEADER

echo '  [studio] User: "tell laptop to pull the image and flash it"'
echo ""
echo '  [studio] $ xw send --to laptop task "OpenWrt image build complete.'
echo '    Pull via: scp studio:travel-router/_build/openwrt-rpi5.img.gz .'
echo '    Flash to 32GB SD card and report when Pi boots."'

# Extract just the hex ID from send output like "Sent task to laptop [9fbf916a]"
extract_id() { grep -o '\[[a-f0-9]*\]' | tr -d '[]'; }

MSG1=$(studio send --to laptop task "OpenWrt image build complete.
Pull via: scp studio:travel-router/_build/openwrt-rpi5.img.gz .
Flash to 32GB SD card with:
  gunzip -k openwrt-rpi5.img.gz
  sudo dd if=openwrt-rpi5.img of=/dev/diskN bs=4M status=progress
Report back when the Pi boots and connects to WiFi." | extract_id)

echo "  → Sent: $MSG1"
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "  [laptop] $ xw check"
echo -n "  "
laptop check
echo ""
echo "  [laptop] $ xw read $MSG1"
laptop read "$MSG1" | sed 's/^/  /'
echo ""
echo '  [laptop] — Flashes SD card, boots the Pi, tests connectivity...'
echo ""
echo '  [laptop] $ xw send reply --re '"$MSG1"' "Image flashed, Pi booted.'
echo '    WiFi AP is up. BUT: DNS not resolving.'
echo '    Suspect nftables kill switch blocking port 53."'

MSG2=$(laptop send reply --re "$MSG1" "Image flashed and Pi booted.
WiFi AP is up (SSID: TravelRouter). Connected successfully.
BUT: DNS not resolving. curl google.com fails.
dnsmasq is running but upstream queries timeout.
Suspect the nftables kill switch is blocking port 53." | extract_id)

echo "  → Sent: $MSG2"
laptop done "$MSG1" > /dev/null 2>&1
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "  [studio] $ xw check"
echo -n "  "
studio check
echo ""
echo "  [studio] $ xw read $MSG2"
studio read "$MSG2" | sed 's/^/  /'
echo ""
echo '  [studio] — Analyzes the build config, finds the root cause...'
echo ""
echo '  [studio] $ xw send reply --re '"$MSG2"' "Found it. Port 53 exemption'
echo '    missing in nftables. Apply this fix on the Pi."'

MSG3=$(studio send reply --re "$MSG2" "Found it. Port 53 exemption missing in nftables output chain.
The kill switch blocks all non-VPN traffic including DNS.
Fix: add this rule before the reject line:
  nft add rule inet fw4 output udp dport 53 accept
Apply on the Pi and test again." | extract_id)

echo "  → Sent: $MSG3"
studio done "$MSG2" > /dev/null 2>&1
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "  [laptop] $ xw check"
echo -n "  "
laptop check
echo ""
echo '  [laptop] — SSHes into Pi, applies the nftables rule, tests...'
echo ""
echo '  [laptop] $ xw send reply --re '"$MSG3"' "ALL WORKING!'
echo '    DNS resolves, VPN active, xray clean."'

MSG4=$(laptop send reply --re "$MSG3" "ALL WORKING!
DNS: google.com resolves via 127.0.0.1 (dnsmasq)
VPN: curl ifconfig.me returns 203.0.113.42 (Hetzner server)
Xray log: clean, no errors
Travel router is fully operational." | extract_id)

echo "  → Sent: $MSG4"
laptop done "$MSG3" > /dev/null 2>&1
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "  [studio] $ xw read $MSG4"
studio read "$MSG4" | sed 's/^/  /'
studio done "$MSG4" > /dev/null 2>&1
echo ""
echo "  [studio] $ xw peers"
studio peers | sed 's/^/  /'

cat << 'FOOTER'

════════════════════════════════════════════════════════════════
  4 messages. Bug found, diagnosed, fixed, verified.
  Two agents, two machines, one conversation thread.
════════════════════════════════════════════════════════════════
FOOTER
