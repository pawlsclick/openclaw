#!/bin/bash
# Run this on the EC2 instance (as ubuntu or root) to fix in place after cloud-init
# user-data failure. Usage: scp to instance and bash fix-userdata-in-place.sh

set -e

OPENCLAW_DIR=/home/ubuntu/openclaw
export DEBIAN_FRONTEND=noninteractive

# 0) Install Docker if missing (idempotent)
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl git
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  usermod -aG docker ubuntu
fi
CONFIG_DIR=/home/ubuntu/.openclaw
WORKSPACE_DIR=/home/ubuntu/.openclaw/workspace

# 1) Ensure dirs and repo exist
sudo mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"
sudo chown -R ubuntu:ubuntu "$CONFIG_DIR"
if [ ! -f "$OPENCLAW_DIR/package.json" ]; then
  sudo -u ubuntu git clone --depth 1 https://github.com/openclaw/openclaw.git "$OPENCLAW_DIR"
fi
cd "$OPENCLAW_DIR"
sudo chown -R ubuntu:ubuntu "$OPENCLAW_DIR"

# 2) .env (standard ports 18789 gateway, 18790 bridge)
sudo -u ubuntu tee .env << 'ENVEOF'
OPENCLAW_IMAGE=openclaw:latest
OPENCLAW_GATEWAY_TOKEN=set-on-first-ssh
OPENCLAW_GATEWAY_BIND=loopback
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_BRIDGE_PORT=18790
OPENCLAW_CONFIG_DIR=/home/ubuntu/.openclaw
OPENCLAW_WORKSPACE_DIR=/home/ubuntu/.openclaw/workspace
ENVEOF

# 3) Loopback-only port mapping: host 18789/18790 -> container 18789/18790 (no port conflict)
sudo -u ubuntu tee docker-compose.override.yml << 'OVERRIDEEOF'
services:
  openclaw-gateway:
    ports:
      - "127.0.0.1:18789:18789"
      - "127.0.0.1:18790:18790"
OVERRIDEEOF

# 4) Build and start (use sudo so docker works if ubuntu not in docker group yet)
# Stop service and tear down stack so host ports 18789/18790 are released (fixes "address already in use")
sudo systemctl stop openclaw-docker.service 2>/dev/null || true
sudo docker compose down --remove-orphans 2>/dev/null || true
sudo docker build -t openclaw:latest -f Dockerfile .
sudo docker compose up -d

# 5) Start on reboot
sudo tee /etc/systemd/system/openclaw-docker.service << 'SVCEOF'
[Unit]
Description=OpenClaw Gateway (Docker Compose)
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/ubuntu/openclaw
ExecStart=/usr/bin/docker compose up -d
User=ubuntu
Group=ubuntu

[Install]
WantedBy=multi-user.target
SVCEOF
sudo systemctl enable openclaw-docker.service

echo "Done. Set token: cd $OPENCLAW_DIR && sudo docker compose run --rm openclaw-cli config set gateway.auth.token \"\$(openssl rand -hex 32)\""
echo "Tunnel (standard port 18789): ssh -N -L 18789:127.0.0.1:18789 -i KEY.pem ubuntu@HOST"
