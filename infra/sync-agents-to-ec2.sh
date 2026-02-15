#!/usr/bin/env bash
set -euo pipefail

KEY_PATH="$HOME/.ssh/awspawlclick.pem"
REMOTE_USER="ubuntu"
REMOTE_HOST="13.49.29.250"
REMOTE_DIR="/home/ubuntu/openclaw/src/agents"

LOCAL_BASE="/Users/woodrowbrown/Projects/openclaw/src/agents"

scp -i "$KEY_PATH" \
  "$LOCAL_BASE/models-config.ts" \
  "$LOCAL_BASE/pi-embedded-runner/run.ts" \
  "$LOCAL_BASE/pi-embedded-runner/compact.ts" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"
