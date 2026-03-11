#!/usr/bin/env bash
# Animated demo for VHS recording — runs real xw commands with narration
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Colors
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
WHITE='\033[97m'
RESET='\033[0m'

narrate() { printf "${DIM}${WHITE}%s${RESET}\n" "$1"; }
user_says() { printf "\n${BOLD}${YELLOW}▸ User:${RESET} ${BOLD}${WHITE}\"%s\"${RESET}\n\n" "$1"; sleep 1.5; }
agent_label() { printf "${BOLD}${1}[%s]${RESET} " "$2"; }
show_cmd() { printf "  ${DIM}$ %s${RESET}\n" "$1"; }
pause() { sleep "${1:-1}"; }

# ── Setup (silent) ──
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
extract_id() { grep -o '\[[a-f0-9]*\]' | tr -d '[]'; }

mkdir -p "$HUB_PARENT"
studio init-hub --path "$HUB_PARENT" > /dev/null 2>&1
studio join --name studio --hub "$HUB" > /dev/null 2>&1
laptop join --name laptop --hub "$HUB" > /dev/null 2>&1
studio sync > /dev/null 2>&1

# ── Scene 1: Studio sends task ──
printf "${BOLD}${CYAN}━━━ crosswire demo ━━━${RESET}\n"
printf "${DIM}Two agents, two machines, one conversation${RESET}\n\n"
sleep 2

agent_label "$GREEN" "studio"
narrate "Mac Studio — has all source code and build toolchain"
agent_label "$BLUE" "laptop"
narrate "MacBook Pro — physically connected to Raspberry Pi via USB"
echo ""
sleep 2

user_says "tell laptop to pull the image and flash the SD card"

agent_label "$GREEN" "studio"
printf "${WHITE}Sending task to laptop...${RESET}\n"
show_cmd 'xw send --to laptop task "Image ready. Flash SD card, boot Pi, report back."'
MSG1=$(studio send --to laptop task "OpenWrt image build complete.
Pull via scp, flash the 32GB SD card, boot the Pi, and tell me what happens." | extract_id)
printf "  ${GREEN}→ Sent: ${MSG1}${RESET}\n"
sleep 2.5

# ── Scene 2: Laptop checks inbox ──
echo ""
agent_label "$BLUE" "laptop"
printf "${WHITE}Checking inbox...${RESET}\n"
show_cmd "xw check"
laptop check | sed 's/^/  /'
sleep 1.5

show_cmd "xw read ${MSG1}"
laptop read "$MSG1" | sed 's/^/  /'
sleep 2.5

# ── Scene 3: Laptop reports DNS bug ──
echo ""
agent_label "$BLUE" "laptop"
printf "${WHITE}Flashes SD card, boots Pi... WiFi works, but DNS is broken.${RESET}\n"
pause 1.5
narrate "Reporting back to studio:"
show_cmd 'xw send reply --re '"$MSG1"' "DNS broken. nftables blocking port 53."'
MSG2=$(laptop send reply --re "$MSG1" "Pi booted. WiFi AP is up (SSID: TravelRouter).
BUT: DNS not resolving. dnsmasq can't reach upstream.
Suspect nftables kill switch is blocking port 53." | extract_id)
printf "  ${BLUE}→ Sent: ${MSG2}${RESET}\n"
laptop done "$MSG1" > /dev/null 2>&1
sleep 2.5

# ── Scene 4: Studio diagnoses, sends fix ──
echo ""
agent_label "$GREEN" "studio"
printf "${WHITE}Reading report...${RESET}\n"
show_cmd "xw read ${MSG2}"
studio read "$MSG2" | sed 's/^/  /'
sleep 2

agent_label "$GREEN" "studio"
printf "${WHITE}Analyzed build config — found root cause.${RESET}\n"
pause 1.5

user_says "tell laptop to apply the nftables fix"

show_cmd 'xw send reply --re '"$MSG2"' "Port 53 exemption missing. Apply fix."'
MSG3=$(studio send reply --re "$MSG2" "Found it. Port 53 not exempted in nftables output chain.
Apply: nft add rule inet fw4 output udp dport 53 accept
Then test DNS again." | extract_id)
printf "  ${GREEN}→ Sent: ${MSG3}${RESET}\n"
studio done "$MSG2" > /dev/null 2>&1
sleep 2.5

# ── Scene 5: Laptop applies fix, all working ──
echo ""
agent_label "$BLUE" "laptop"
printf "${WHITE}Applies fix on Pi, tests again...${RESET}\n"
pause 1.5
show_cmd 'xw send reply --re '"$MSG3"' "ALL WORKING!"'
MSG4=$(laptop send reply --re "$MSG3" "ALL WORKING!
DNS: google.com resolves via 127.0.0.1 (dnsmasq)
VPN: curl ifconfig.me returns 203.0.113.42 (Hetzner)
Xray log: clean, no errors
Travel router fully operational." | extract_id)
printf "  ${BLUE}→ Sent: ${MSG4}${RESET}\n"
laptop done "$MSG3" > /dev/null 2>&1
sleep 2

# ── Scene 6: Studio reads success ──
echo ""
agent_label "$GREEN" "studio"
printf "${WHITE}Reading final report...${RESET}\n"
show_cmd "xw read ${MSG4}"
studio read "$MSG4" | sed 's/^/  /'
studio done "$MSG4" > /dev/null 2>&1
sleep 2

# ── Summary ──
echo ""
printf "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${BOLD}${WHITE}  ✓ 4 messages. Bug found → diagnosed → fixed → verified.${RESET}\n"
printf "${BOLD}${WHITE}  ✓ Two agents, two machines, one conversation thread.${RESET}\n"
printf "${BOLD}${WHITE}  ✓ Plain text files over SSH. Zero dependencies.${RESET}\n"
printf "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
sleep 4
