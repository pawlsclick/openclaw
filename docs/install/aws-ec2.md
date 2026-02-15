---
summary: "Run OpenClaw Gateway on AWS EC2 via CloudFormation (Ubuntu 24.04, Docker, SSH tunnel)"
read_when:
  - You want OpenClaw on EC2 in a specific VPC/subnet
  - You prefer infra-as-code (CloudFormation) for the instance
title: "AWS EC2"
---

# OpenClaw on AWS EC2 (CloudFormation)

## Goal

Provision a single Ubuntu 24.04 EC2 instance with Docker, clone OpenClaw, build the image, and run the gateway via Docker Compose. Access is **SSH tunnel only** (no inbound port 18789); the gateway binds to loopback on the host.

This guide uses a CloudFormation template in the repo. Defaults target **eu-north-1** and the specs below; you can override parameters.

## What you need

- AWS CLI configured (account, region, credentials)
- Key pair in the target region (default name: `awspawlclick`); you need the `.pem` locally
- VPC and subnet (defaults in the template; use a **public** subnet if you want a public IP for SSH)
- Security group that allows **inbound SSH (22)** from your IP (no inbound 18789)
- About 15–20 minutes (first run: instance boot + Docker install + image build)

## 1) Verify AWS connectivity

Confirm the CLI and (optional) MCP can reach your account and the resources you will use.

**AWS CLI:**

```bash
aws sts get-caller-identity
aws ec2 describe-vpcs --vpc-ids vpc-05c0d292bf26d7bd1 --region eu-north-1
aws ec2 describe-subnets --subnet-ids subnet-0954f659cbd458cca --region eu-north-1
aws ec2 describe-security-groups --group-ids sg-06969578c0d2792ef --region eu-north-1
```

Ensure the security group allows **inbound TCP 22** from your IP (or 0.0.0.0/0 for testing only). There should be **no** inbound rule for port 18789 (access is via SSH tunnel).

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
    ParameterKey=InstanceType,ParameterValue=t3.medium \
    ParameterKey=BootVolumeSizeGb,ParameterValue=30
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

## 3) First SSH and set the gateway token

User-data installs Docker, clones the repo, builds the image, and starts the gateway. The first time may take several minutes. Then:

```bash
ssh -i awspawlclick.pem ubuntu@<PublicIp>
```

On the instance, generate a gateway token and write it into the config used by the container. Easiest: run the CLI in a one-off container so it uses the same volumes:

```bash
cd /home/ubuntu/openclaw
docker compose run --rm openclaw-cli config set gateway.auth.token "$(openssl rand -hex 32)"
```

Or edit the host config (mounted into the container):

```bash
# View current config
cat /home/ubuntu/.openclaw/openclaw.json

# Add or set gateway.auth.token; then restart so the gateway picks it up
docker compose -f /home/ubuntu/openclaw/docker-compose.yml restart openclaw-gateway
```

Get a dashboard link with the token (optional):

```bash
docker compose run --rm openclaw-cli dashboard --no-open
```

Exit the SSH session when done.

## 4) Access the Control UI via SSH tunnel

From your **laptop**, open an SSH tunnel so that local port 18789 forwards to the gateway on the instance:

```bash
ssh -N -L 18789:127.0.0.1:18789 -i awspawlclick.pem ubuntu@<PublicIp>
```

Leave this terminal running. Then in your browser open:

**http://127.0.0.1:18789/**

Paste the gateway token (from step 3) when prompted. You can now use the Control UI and chat.

## 5) Security group summary

- **Inbound 22 (SSH):** Required from your IP (or 0.0.0.0/0 for testing).
- **No inbound 18789:** Access to the gateway is only via the SSH tunnel above.

## 6) Restart and persistence

- The template enables a systemd unit `openclaw-docker.service` so that on instance reboot, `docker compose up -d` runs in `/home/ubuntu/openclaw`.
- Config and workspace live in `/home/ubuntu/.openclaw` and `/home/ubuntu/.openclaw/workspace` on the host and are mounted into the container; they persist across container and instance restarts.

## 7) Template location and parameters

The CloudFormation template is at **`infra/aws/openclaw-ec2.yaml`** in the repo.

Main parameters (with defaults):

| Parameter           | Default                       | Description                          |
| ------------------- | ----------------------------- | ------------------------------------ |
| KeyName             | awspawlclick                  | EC2 key pair name                    |
| InstanceType        | t3.medium                     | Instance type                         |
| VpcId               | vpc-05c0d292bf26d7bd1         | VPC ID                               |
| SubnetId            | subnet-0954f659cbd458cca      | Subnet ID (use public for public IP) |
| SecurityGroupId     | sg-06969578c0d2792ef          | Security group (SSH only; no 18789)  |
| BootVolumeSizeGb    | 30                            | Root EBS gp3 size (GB)                |
| AmiId               | (SSM Ubuntu 24.04 LTS)        | AMI; override to pin a specific ID   |

## See also

- [VPS hosting hub](/vps) — overview of cloud deployments
- [Docker](/install/docker) — generic Docker Gateway flow
- [Gateway remote](/gateway/remote) — SSH tunnel and remote client config
