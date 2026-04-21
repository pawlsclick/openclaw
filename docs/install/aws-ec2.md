---
summary: "Run OpenClaw Gateway on AWS EC2 via CloudFormation (Ubuntu 24.04, direct install, Xfce+RDP)"
read_when:
  - You want OpenClaw on EC2 in a specific VPC/subnet
  - You prefer infra-as-code (CloudFormation) for the instance
title: "AWS EC2"
---

# OpenClaw on AWS EC2 (CloudFormation)

## Goal

Provision a single vanilla Ubuntu 24.04 EC2 instance. UserData installs **Xfce** desktop, **xrdp** (port 3389), Node 22, and OpenClaw via `npm install -g openclaw@latest`; the gateway runs under systemd (loopback bind). Access: **SSH tunnel** for Control UI (port 18789) and **RDP** for the desktop (port 3389). No Docker; no repo clone.

This guide uses a CloudFormation template in the repo. Defaults target **eu-north-1** and the specs below; you can override parameters.

## What you need

- AWS CLI configured (account, region, credentials)
- Key pair in the target region (default name: `awspawlclick`); you need the `.pem` locally
- VPC and subnet (defaults in the template; use a **public** subnet if you want a public IP for SSH and RDP)
- Security group **sg-06969578c0d2792ef** (template default) must allow **inbound SSH (22)** and **inbound RDP (3389)** from your IP; **no** inbound 18789
- About 10–15 minutes (first run: instance boot + Xfce + xrdp + OpenClaw install)

## 1) Verify AWS connectivity

Confirm the CLI and (optional) MCP can reach your account and the resources you will use.

**AWS CLI:**

```bash
aws sts get-caller-identity
aws ec2 describe-vpcs --vpc-ids vpc-05c0d292bf26d7bd1 --region eu-north-1
aws ec2 describe-subnets --subnet-ids subnet-0954f659cbd458cca --region eu-north-1
aws ec2 describe-security-groups --group-ids sg-06969578c0d2792ef --region eu-north-1
```

Ensure the security group allows **inbound TCP 22** and **inbound TCP 3389** from your IP (or 0.0.0.0/0 for testing only). There should be **no** inbound rule for port 18789 (access is via SSH tunnel).

**Optional:** If you use the AWS MCP tool in Cursor, run equivalent describe calls for the same VPC, subnet, and security group in `eu-north-1`.

## 2) Deploy the stack

From the repo root:

```bash
aws cloudformation create-stack \
  --region eu-north-1 \
  --stack-name openclaw-gateway \
  --template-body file://infra/aws/openclaw-ec2.yaml \
  --parameters \
    ParameterKey=KeyName,ParameterValue=awspawlclick \
    ParameterKey=InstanceType,ParameterValue=t3.large
```

To use a different VPC, subnet, or security group, add or override parameters (e.g. `ParameterKey=VpcId,ParameterValue=vpc-xxxx`).

Wait for the stack to reach `CREATE_COMPLETE`:

```bash
aws cloudformation wait stack-create-complete \
  --region eu-north-1 \
  --stack-name openclaw-gateway
```

Get the instance ID and public IP from the stack outputs:

```bash
aws cloudformation describe-stacks \
  --region eu-north-1 \
  --stack-name openclaw-gateway \
  --query 'Stacks[0].Outputs'
```

Note the `PublicIp` (and `InstanceId` if needed). If `PublicIp` is empty, the instance is in a private subnet; use a bastion or VPN to reach it.

## 3) Get the gateway token and (optional) set RDP password

UserData installs Xfce, xrdp, Node 22, OpenClaw, and a systemd gateway; it also generates a gateway token and writes it to a file. After the stack reaches `CREATE_COMPLETE`, wait a few minutes for first-boot setup to finish, then fetch the token:

```bash
ssh -i awspawlclick.pem ubuntu@<PublicIp> 'cat /home/ubuntu/.openclaw/gateway-token.txt'
```

Save this token; you will paste it into the Control UI (step 4). Optionally, set a password for the `ubuntu` user so you can log in via RDP:

```bash
ssh -i awspawlclick.pem ubuntu@<PublicIp>
sudo passwd ubuntu
# Enter new password when prompted, then exit
```

## 4) Access the Control UI via SSH tunnel

From your **laptop**, open an SSH tunnel so that local port 18789 forwards to the gateway on the instance:

```bash
ssh -N -L 18789:127.0.0.1:18789 -i awspawlclick.pem ubuntu@<PublicIp>
```

Leave this terminal running. Then in your browser open:

**http://127.0.0.1:18789/**

Paste the gateway token (from step 3) when prompted. You can now use the Control UI and chat.

## 5) Connect via RDP (desktop)

From your laptop, connect to the instance’s desktop using an RDP client (Windows Remote Desktop, Remmina, etc.):

- **Address:** `<PublicIp>:3389` (use the `PublicIp` from the stack outputs)
- **User:** `ubuntu`
- **Password:** Set in step 3 with `sudo passwd ubuntu`, or use SSH key auth if your RDP client supports it

The template installs Xfce and xrdp; you get a full desktop for GUI apps and optional [agent GUI automation](#xrdp--xfce-gui-automation-and-screen-capture).

## 6) Security group summary

- **Inbound 22 (SSH):** Required from your IP (or 0.0.0.0/0 for testing).
- **Inbound 3389 (RDP):** Required from your IP if you use RDP.
- **No inbound 18789:** Access to the gateway is only via the SSH tunnel above.

## 7) Restart and persistence

- The template enables a systemd unit `openclaw-gateway.service` so that on instance reboot, the gateway runs as the `ubuntu` user (`openclaw gateway run --bind loopback --port 18789`).
- Config and workspace live in `~/.openclaw` and `~/.openclaw/workspace` on the host and persist across reboots.

## 8) Template location and parameters

The CloudFormation template is at **`infra/aws/openclaw-ec2.yaml`** in the repo.

Main parameters (with defaults):

| Parameter           | Default                       | Description                                                |
| ------------------- | ----------------------------- | ---------------------------------------------------------- |
| KeyName             | awspawlclick                  | EC2 key pair name                                         |
| InstanceType        | t3.large                      | Instance type                                              |
| VpcId               | vpc-05c0d292bf26d7bd1         | VPC ID                                                     |
| SubnetId            | subnet-0954f659cbd458cca      | Subnet ID (use public for public IP)                      |
| SecurityGroupId     | sg-06969578c0d2792ef          | Security group (must allow inbound 22 and 3389; no 18789)  |
| BootVolumeSizeGb    | 300                           | Root EBS gp3 size (GiB); max 500 in template              |
| AmiId               | ami-073130f74f5ffb161         | Vanilla Ubuntu 24.04 LTS AMI (direct-install UserData)    |

## Grow root disk on a running instance

Use this when the gateway host is low on disk and you want a **larger root volume without replacing the instance**.

**Do not** try to fix disk only by increasing `BootVolumeSizeGb` and running a stack update on an existing instance: changing root `Ebs.VolumeSize` in `BlockDeviceMappings` can **replace** the EC2 instance (see comments on `BootVolumeSizeGb` in the template).

**Approach:** From your laptop (AWS CLI, **`jq`** for SSM payload assembly, same account as the instance), run the automation script. It creates an EBS **snapshot** (wait until completed), calls **`modify-volume`** to grow the gp3 volume, waits for the modification, then uses **SSM** (`AWS-RunShellScript`) to run **`growpart`** and **`resize2fs`** on the Ubuntu root filesystem. The instance must report **SSM PingStatus Online** (SSM agent + instance profile).

From the repo root:

```bash
chmod +x infra/aws/resize-openclaw-root-volume.sh
./infra/aws/resize-openclaw-root-volume.sh \
  --region eu-north-1 \
  --instance-id i-0123456789abcdef0 \
  --target-gib 300
```

Optional: pass `--volume-id vol-...` if root volume detection fails. Break-glass only: `--skip-snapshot I_ACCEPT_NO_SNAPSHOT` skips the snapshot (not recommended).

If the script exits while waiting for the snapshot but the snapshot later shows **completed** in the EC2 console, **do not** re-run without `--existing-snapshot-id` or you will start a second full snapshot. Resume with the same snapshot id (the script checks it belongs to the instance root volume):

```bash
./infra/aws/resize-openclaw-root-volume.sh \
  --region eu-north-1 \
  --instance-id i-0123456789abcdef0 \
  --target-gib 300 \
  --existing-snapshot-id snap-0123456789abcdef0
```

The default wait for snapshot completion is up to **four hours** (`RESIZE_SNAPSHOT_WAIT_SEC`, override if needed).

After a successful run, the script prints `df` output from the instance. If you need to **restore from the snapshot** (rollback or disaster recovery), use the same snapshot id the script printed and follow AWS: [Replace an Amazon EBS volume using a snapshot](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-restoring-volume.html) (same Availability Zone as the instance; root volume changes usually require **stop** → detach → attach replacement → **start**).

## Updating OpenClaw on the instance

**Direct install on the host (no Docker):** If OpenClaw is installed in `/home/ubuntu` (e.g. from source or a clone) or globally via npm:

```bash
ssh -i awspawlclick.pem ubuntu@<PublicIp>
# From source in /home/ubuntu:
cd /home/ubuntu/openclaw
git pull --rebase origin main
pnpm install && pnpm build
# Restart the gateway (however you run it: terminal, systemd, etc.)

# Or global npm:
sudo npm i -g openclaw@latest
# or pin: sudo npm i -g openclaw@2026.2.13
# Then restart the gateway
```

Config and workspace live in `~/.openclaw` (e.g. `/home/ubuntu/.openclaw`). Restart the gateway after updating.

**Docker setup:** If you use the alternative Docker flow (clone repo, Docker Compose) instead of the default direct-install template:

```bash
cd /home/ubuntu/openclaw
git pull --rebase origin main
docker compose build --pull openclaw-gateway
docker compose up -d openclaw-gateway
```

## XRDP + Xfce: GUI automation and screen capture

The default template already installs **Xfce**, **xrdp**, and GUI automation tools (**xdotool**, **scrot**, **wmctrl**) on the host. This section applies when OpenClaw runs **directly on the host** (the default after stack create). To let the agent run GUI apps, automate keyboard/mouse, and capture the screen for vision, the gateway must run in an environment where **DISPLAY** is set (e.g. from a terminal inside your RDP session).

### 1. GUI tools (already installed by UserData)

The template installs `xdotool`, `scrot`, and `wmctrl`. If you ever need to reinstall:

```bash
sudo apt-get update
sudo apt-get install -y xdotool scrot wmctrl
```

### 2. Run the gateway with DISPLAY set

The agent’s `bash` (exec) runs in the gateway’s environment. For GUI apps and xdotool to target your Xfce session, that environment must have `DISPLAY` set to the same value as your RDP session.

**Option A — From a terminal inside your RDP session (simplest):**

1. Connect via RDP and open a terminal in Xfce.
2. In that terminal, run:
   ```bash
   export DISPLAY=:10
   openclaw gateway run --port 18789 --verbose
   ```
   (Use the value your session actually uses: in the same terminal run `echo $DISPLAY` and use that, often `:10` or `:0` for the first xrdp session.)
3. Leave that terminal running. Commands the agent runs via exec will then see the same DISPLAY and can open Firefox, use xdotool, etc., on the desktop you see.

**Option B — Gateway as a user service with fixed DISPLAY:**

If you run the gateway as a systemd user service, set DISPLAY in the unit so it matches the RDP session (e.g. `:10`):

```ini
# ~/.config/systemd/user/openclaw-gateway.service
[Service]
Environment=DISPLAY=:10
ExecStart=/usr/bin/openclaw gateway run --port 18789
Restart=on-failure
```

Then start the service **after** you have logged in at least once via RDP (so the X server for that display exists). Reload and start:

```bash
systemctl --user daemon-reload
systemctl --user enable --now openclaw-gateway
```

### 3. Use a vision-capable model

In `~/.openclaw/openclaw.json` (or your config), set an agent model that supports images (e.g. Claude, GPT-4V, Gemini). When the agent runs `scrot /tmp/screen.png` and then references `MEDIA:/tmp/screen.png` in a message or tool result, the model will receive the image.

Example (adjust model id to your provider):

```json
{
  "agent": {
    "model": "anthropic/claude-sonnet-4-20250514"
  }
}
```

### 4. Optional: tell the agent about GUI capabilities

Add a short note in the workspace so the agent knows it can use the desktop (e.g. in `~/.openclaw/workspace/AGENTS.md` or a SOUL/TOOLS note):

- On this host, the agent can run GUI apps (e.g. `firefox`, `xfce4-terminal`) and automation tools (`xdotool`, `wmctrl`). Use `scrot` (or `scrot /tmp/screen.png`) to capture the screen; then reference `MEDIA:/tmp/screen.png` (or the path you used) so the model can analyze the screenshot with vision.

With that in place you get:

- **Run GUI software** — agent runs `firefox`, `xfce4-terminal`, etc., and they appear on your Xfce desktop.
- **GUI automation** — agent uses `xdotool` (and optionally `wmctrl`) for keyboard/mouse and window control.
- **Screen capture and vision** — agent runs `scrot`, then uses the saved image path with a vision-capable model to “see” the desktop.

**Check what is in place:** Run `./scripts/check-gui-automation.sh [path]`. It writes a Markdown report (default: `./gui-automation-report.md`) with a Summary table, Details, and **Next steps**. Paste the file contents or attach the file to your assistant to confirm state and get follow-up actions. Run the script from the same environment where you start the gateway (e.g. inside your RDP session).

## See also

- [VPS hosting hub](/vps) — overview of cloud deployments
- [Docker](/install/docker) — generic Docker Gateway flow
- [Gateway remote](/gateway/remote) — SSH tunnel and remote client config
- [Exec tool](/tools/exec) — command execution and host/sandbox
