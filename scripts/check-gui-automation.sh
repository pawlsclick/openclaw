#!/usr/bin/env bash
# Report what is in place on this host for OpenClaw GUI automation (Xfce/XRDP,
# DISPLAY, xdotool, screenshots, OpenClaw, etc.). Writes a Markdown file you can
# pass to an assistant to determine state and next steps. Read-only; safe to run anytime.
#
# Usage: ./scripts/check-gui-automation.sh [output-path]
#   Default output: ./gui-automation-report.md (current directory)
#   Example: ./scripts/check-gui-automation.sh ~/gui-automation-report.md

set -euo pipefail

REPORT_FILE="${1:-./gui-automation-report.md}"
NEXT_STEPS=()

report() { printf '%s\n' "$@"; }
append() { echo "$*" >> "$REPORT_FILE"; }

# --- Collect data ---
DISPLAY_VAL="${DISPLAY:-}"
USER_VAL="${USER:-}"
HOME_VAL="${HOME:-<unset>}"

XRDP_ACTIVE=false
XRDP_SESMAN_ACTIVE=false
if command -v systemctl &>/dev/null; then
  systemctl is-active --quiet xrdp 2>/dev/null && XRDP_ACTIVE=true
  systemctl is-active --quiet xrdp-sesman 2>/dev/null && XRDP_SESMAN_ACTIVE=true
fi

XSESSION_EXISTS=false
XSESSION_FIRST=""
[[ -f "$HOME/.xsession" ]] && XSESSION_EXISTS=true && XSESSION_FIRST=$(head -n1 "$HOME/.xsession" 2>/dev/null || true)

HAS_XDOTOOL=false; HAS_WMCTRL=false; HAS_SCROT=false
command -v xdotool &>/dev/null && HAS_XDOTOOL=true
command -v wmctrl &>/dev/null && HAS_WMCTRL=true
command -v scrot &>/dev/null && HAS_SCROT=true

XDOTOOL_PATH=""; WMCTRL_PATH=""; SCROT_PATH=""
$HAS_XDOTOOL && XDOTOOL_PATH=$(command -v xdotool)
$HAS_WMCTRL && WMCTRL_PATH=$(command -v wmctrl)
$HAS_SCROT && SCROT_PATH=$(command -v scrot)

HAS_XFCE=false; HAS_FIREFOX=false
command -v xfce4-session &>/dev/null && HAS_XFCE=true
command -v firefox &>/dev/null && HAS_FIREFOX=true
command -v firefox-esr &>/dev/null && HAS_FIREFOX=true

X_REACHABLE=""; XDOTOOL_QUERY=""
if [[ -n "$DISPLAY_VAL" ]] && command -v xdpyinfo &>/dev/null; then
  xdpyinfo -display "$DISPLAY_VAL" &>/dev/null && X_REACHABLE=yes || X_REACHABLE=no
fi
if [[ -n "$DISPLAY_VAL" ]] && command -v xdotool &>/dev/null; then
  xdotool getmouselocation &>/dev/null 2>&1 && XDOTOOL_QUERY=yes || XDOTOOL_QUERY=no
fi

HAS_OPENCLAW=false; OPENCLAW_PATH=""; OPENCLAW_VERSION=""
command -v openclaw &>/dev/null && HAS_OPENCLAW=true && OPENCLAW_PATH=$(command -v openclaw)
OPENCLAW_VERSION=$(openclaw --version 2>/dev/null || true)

HAS_OPENCLAW_DIR=false; HAS_OPENCLAW_JSON=false; HAS_WORKSPACE=false
[[ -d "${HOME}/.openclaw" ]] && HAS_OPENCLAW_DIR=true
[[ -f "$HOME/.openclaw/openclaw.json" ]] && HAS_OPENCLAW_JSON=true
[[ -d "$HOME/.openclaw/workspace" ]] && HAS_WORKSPACE=true

GATEWAY_RUNNING=false
command -v pgrep &>/dev/null && pgrep -f "openclaw.*gateway" &>/dev/null && GATEWAY_RUNNING=true

# --- Build next steps from gaps ---
[[ -z "$DISPLAY_VAL" ]] && NEXT_STEPS+=("Set DISPLAY when starting the gateway (e.g. export DISPLAY=:10 in the same terminal, or in systemd Environment=DISPLAY=:10).")
! $XRDP_ACTIVE && NEXT_STEPS+=("Start xrdp: sudo systemctl start xrdp (and xrdp-sesman if needed).")
! $XSESSION_EXISTS && NEXT_STEPS+=("Create ~/.xsession with e.g. echo 'xfce4-session' > ~/.xsession so RDP logins start Xfce.")
! $HAS_XDOTOOL && NEXT_STEPS+=("Install xdotool: sudo apt-get install -y xdotool")
! $HAS_SCROT && NEXT_STEPS+=("Install screenshot tool: sudo apt-get install -y scrot (or gnome-screenshot)")
! $HAS_WMCTRL && NEXT_STEPS+=("Optional: install wmctrl for window listing/focus: sudo apt-get install -y wmctrl")
! $HAS_XFCE && NEXT_STEPS+=("Install Xfce: sudo apt-get install -y xfce4 xfce4-goodies")
! $HAS_FIREFOX && NEXT_STEPS+=("Install Firefox: sudo apt-get install -y firefox (or firefox-esr)")
if [[ -n "$DISPLAY_VAL" ]]; then
  [[ "$X_REACHABLE" == "no" ]] && NEXT_STEPS+=("X server on $DISPLAY_VAL is not reachable (xdpyinfo failed). Ensure the gateway runs in the same session as your RDP desktop.")
  [[ "$XDOTOOL_QUERY" == "no" ]] && NEXT_STEPS+=("xdotool cannot query the display. Check DISPLAY and that no other display/session is blocking.")
fi
! $HAS_OPENCLAW && NEXT_STEPS+=("Install OpenClaw (e.g. from source in /home/ubuntu/openclaw or: sudo npm i -g openclaw@latest).")
! $HAS_OPENCLAW_DIR && NEXT_STEPS+=("Create OpenClaw config: run openclaw onboard or ensure ~/.openclaw exists with openclaw.json.")
! $GATEWAY_RUNNING && NEXT_STEPS+=("Start the gateway (e.g. openclaw gateway run --port 18789) in an environment where DISPLAY is set if you need GUI automation.")

# --- Write report ---
{
  report "# GUI automation setup report"
  report ""
  report "Pass this file to your assistant to see what is in place and what to do next."
  report ""
  report "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)"
  report "Host: $(hostname 2>/dev/null || echo 'unknown')"
  report "User: $USER_VAL"
  report ""
  report "---"
  report ""
  report "## Summary"
  report ""
  report "| Component | Status | Notes |"
  report "|-----------|--------|-------|"
  report "| DISPLAY | $([ -n "$DISPLAY_VAL" ] && echo "OK" || echo "MISSING") | ${DISPLAY_VAL:-<not set>} |"
  report "| XRDP | $( $XRDP_ACTIVE && echo "OK" || echo "inactive") | xrdp.service |"
  report "| XRDP sesman | $( $XRDP_SESMAN_ACTIVE && echo "OK" || echo "inactive") | xrdp-sesman.service |"
  report "| ~/.xsession | $( $XSESSION_EXISTS && echo "OK" || echo "MISSING") | ${XSESSION_FIRST:-<none>} |"
  report "| xdotool | $( $HAS_XDOTOOL && echo "OK" || echo "MISSING") | ${XDOTOOL_PATH:-<not in PATH>} |"
  report "| wmctrl | $( $HAS_WMCTRL && echo "OK" || echo "optional") | ${WMCTRL_PATH:-<not in PATH>} |"
  report "| scrot | $( $HAS_SCROT && echo "OK" || echo "MISSING") | ${SCROT_PATH:-<not in PATH>} |"
  report "| xfce4-session | $( $HAS_XFCE && echo "OK" || echo "MISSING") | desktop |"
  report "| firefox/firefox-esr | $( $HAS_FIREFOX && echo "OK" || echo "MISSING") | browser |"
  report "| X server reachable | ${X_REACHABLE:-n/a} | when DISPLAY set |"
  report "| xdotool getmouselocation | ${XDOTOOL_QUERY:-n/a} | when DISPLAY set |"
  report "| openclaw CLI | $( $HAS_OPENCLAW && echo "OK" || echo "MISSING") | ${OPENCLAW_PATH:-<not in PATH>} |"
  report "| openclaw version | ${OPENCLAW_VERSION:-<unknown>} | |"
  report "| ~/.openclaw | $( $HAS_OPENCLAW_DIR && echo "OK" || echo "MISSING") | config dir |"
  report "| openclaw.json | $( $HAS_OPENCLAW_JSON && echo "OK" || echo "missing") | |"
  report "| workspace dir | $( $HAS_WORKSPACE && echo "OK" || echo "missing") | |"
  report "| gateway process | $( $GATEWAY_RUNNING && echo "running" || echo "not found") | |"
  report ""
  report "---"
  report ""
  report "## Details"
  report ""
  report "### Environment"
  report "- DISPLAY=$DISPLAY_VAL"
  report "- USER=$USER_VAL"
  report "- HOME=$HOME_VAL"
  report ""
  report "### X session"
  report "- .xsession exists: $XSESSION_EXISTS"
  report "- .xsession first line: $XSESSION_FIRST"
  report ""
  report "### GUI / screenshot tools"
  report "- xdotool: $HAS_XDOTOOL ($XDOTOOL_PATH)"
  report "- wmctrl: $HAS_WMCTRL ($WMCTRL_PATH)"
  report "- scrot: $HAS_SCROT ($SCROT_PATH)"
  report ""
  report "### Desktop and browser"
  report "- xfce4-session: $HAS_XFCE"
  report "- firefox/firefox-esr: $HAS_FIREFOX"
  report ""
  report "### X server (when DISPLAY set)"
  report "- xdpyinfo reachable: $X_REACHABLE"
  report "- xdotool getmouselocation: $XDOTOOL_QUERY"
  report ""
  report "### OpenClaw"
  report "- openclaw: $HAS_OPENCLAW ($OPENCLAW_PATH)"
  report "- version: $OPENCLAW_VERSION"
  report "- ~/.openclaw: $HAS_OPENCLAW_DIR"
  report "- openclaw.json: $HAS_OPENCLAW_JSON"
  report "- workspace: $HAS_WORKSPACE"
  report "- gateway running: $GATEWAY_RUNNING"
  report ""
  report "---"
  report ""
  report "## Next steps"
  report ""
  if [[ ${#NEXT_STEPS[@]} -eq 0 ]]; then
    report "No required next steps; setup appears complete for GUI automation. Ensure the gateway is started with DISPLAY set (e.g. from a terminal inside your RDP session)."
  else
    for i in "${!NEXT_STEPS[@]}"; do
      report "$((i+1)). ${NEXT_STEPS[$i]}"
      report ""
    done
  fi
  report ""
} > "$REPORT_FILE"

echo "Report written to: $REPORT_FILE"
echo ""
echo "To share with an assistant, paste the file contents or attach the file:"
echo "  cat $(realpath "$REPORT_FILE" 2>/dev/null || echo "$REPORT_FILE")"
echo ""
