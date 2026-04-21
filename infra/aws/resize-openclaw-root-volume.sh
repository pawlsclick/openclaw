#!/usr/bin/env bash
# Grow the OpenClaw (or any) EC2 root gp3 volume in place: snapshot → modify-volume → SSM growpart + resize2fs.
# Run from your laptop with admin IAM (ec2 + ssm). Do NOT run on the instance.
#
# Usage:
#   ./resize-openclaw-root-volume.sh --region eu-north-1 --instance-id i-0123... [--volume-id vol-...] [--target-gib 300]
#
# Resume after a snapshot finished but the script timed out (do not re-run without this or you create a second snapshot):
#   ./resize-openclaw-root-volume.sh ... --existing-snapshot-id snap-0123abcdef
#
# Optional: RESIZE_SNAPSHOT_WAIT_SEC (default 14400 = 4 hours) caps how long we poll describe-snapshots.
#
# Break-glass (no snapshot — not recommended):
#   ./resize-openclaw-root-volume.sh ... --skip-snapshot I_ACCEPT_NO_SNAPSHOT
#
# Recovery from snapshot (AWS guide):
#   https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-restoring-volume.html
set -euo pipefail

SKIP_SNAPSHOT_CONFIRM=""
EXISTING_SNAPSHOT_ID=""
TARGET_GIB=300
REGION=""
INSTANCE_ID=""
VOLUME_ID=""

usage() {
  sed -n '1,28p' "$0" | tail -n +2
  exit 1
}

print_snapshot_recovery() {
  local snap="$1"
  echo ""
  echo "--- Recovery baseline (rollback / replace root) ---"
  echo "AWS doc: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-restoring-volume.html"
  echo "Same AZ: $AZ  Instance: $INSTANCE_ID  Root device: $ROOT_DEV  Old volume: $VOLUME_ID"
  echo "Example: create volume from snapshot, stop instance, detach $VOLUME_ID, attach new volume as $ROOT_DEV, start."
  echo "  aws ec2 create-volume --region $REGION --availability-zone $AZ --snapshot-id $snap --volume-type gp3"
  echo "---"
  echo ""
}

# Poll describe-snapshots (aws ec2 wait snapshot-completed often times out around ~10m on large volumes).
wait_for_snapshot_completed() {
  local snap_id="$1"
  local max_sec="${RESIZE_SNAPSHOT_WAIT_SEC:-14400}"
  local started now elapsed
  started=$(date +%s)
  echo "Waiting for snapshot $snap_id to reach completed (max ${max_sec}s, override with RESIZE_SNAPSHOT_WAIT_SEC)..."
  while true; do
    # One line, tab-separated (bash 3.2–compatible; no mapfile).
    read -r state svol prog <<< "$(aws ec2 describe-snapshots --region "$REGION" --snapshot-ids "$snap_id" \
      --query 'Snapshots[0].[State,VolumeId,Progress]' --output text 2>/dev/null || true)"
    if [[ -z "$state" || "$state" == "None" ]]; then
      echo "Could not describe snapshot $snap_id" >&2
      exit 1
    fi
    if [[ "$svol" != "$VOLUME_ID" ]]; then
      echo "Snapshot $snap_id is for volume '$svol', expected root volume '$VOLUME_ID'" >&2
      exit 1
    fi
    now=$(date +%s)
    elapsed=$((now - started))
    if [[ "$state" == "completed" ]]; then
      echo "Snapshot completed (${elapsed}s)."
      return 0
    fi
    if [[ "$state" == "error" ]]; then
      echo "Snapshot $snap_id entered error state." >&2
      exit 1
    fi
    if [[ "$elapsed" -ge "$max_sec" ]]; then
      echo "Timed out after ${elapsed}s waiting for snapshot (state=$state progress=${prog})." >&2
      echo "Re-run with: --existing-snapshot-id $snap_id" >&2
      exit 1
    fi
    echo "  snapshot state=$state progress=${prog} elapsed=${elapsed}s"
    sleep 30
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="${2:?}"; shift 2 ;;
    --instance-id) INSTANCE_ID="${2:?}"; shift 2 ;;
    --volume-id) VOLUME_ID="${2:?}"; shift 2 ;;
    --target-gib) TARGET_GIB="${2:?}"; shift 2 ;;
    --existing-snapshot-id) EXISTING_SNAPSHOT_ID="${2:?}"; shift 2 ;;
    --skip-snapshot)
      SKIP_SNAPSHOT_CONFIRM="${2:?}"
      shift 2
      ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

if [[ -z "$REGION" || -z "$INSTANCE_ID" ]]; then
  echo "Required: --region and --instance-id" >&2
  usage
fi

if ! [[ "$TARGET_GIB" =~ ^[0-9]+$ ]] || [[ "$TARGET_GIB" -lt 16 ]]; then
  echo "--target-gib must be an integer >= 16" >&2
  exit 1
fi

if [[ -n "$EXISTING_SNAPSHOT_ID" && -n "$SKIP_SNAPSHOT_CONFIRM" ]]; then
  echo "Use either --existing-snapshot-id or --skip-snapshot, not both." >&2
  exit 1
fi

if curl -sf --max-time 1 -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -o /tmp/resize-vol-imds-token 2>/dev/null; then
  if [[ -s /tmp/resize-vol-imds-token ]] && curl -sf --max-time 1 -H "X-aws-ec2-metadata-token: $(cat /tmp/resize-vol-imds-token)" \
    "http://169.254.169.254/latest/meta-data/instance-id" -o /dev/null 2>/dev/null; then
    echo "Run this script from your laptop, not on EC2." >&2
    rm -f /tmp/resize-vol-imds-token
    exit 1
  fi
elif curl -sf --max-time 1 "http://169.254.169.254/latest/meta-data/instance-id" -o /dev/null 2>/dev/null; then
  echo "Run this script from your laptop, not on EC2." >&2
  exit 1
fi
rm -f /tmp/resize-vol-imds-token

ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)
if [[ "$ARN" =~ assumed-role/[^/]+/i-[a-f0-9]+$ ]]; then
  echo "Caller looks like an EC2 instance role. Run from your laptop." >&2
  exit 1
fi

ROOT_DEV=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].RootDeviceName' --output text)

if [[ -z "$ROOT_DEV" || "$ROOT_DEV" == "None" ]]; then
  echo "Could not read RootDeviceName for instance ${INSTANCE_ID}." >&2
  exit 1
fi

if [[ -z "$VOLUME_ID" ]]; then
  VOLUME_ID=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].BlockDeviceMappings[?DeviceName=='${ROOT_DEV}'].Ebs.VolumeId | [0]" --output text)
fi

if [[ -z "$VOLUME_ID" || "$VOLUME_ID" == "None" ]]; then
  echo "Could not resolve EBS volume for root device ${ROOT_DEV}. Pass --volume-id explicitly." >&2
  exit 1
fi
AZ=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)

SSM_STATE=$(aws ssm describe-instance-information --region "$REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "Missing")

if [[ "$SSM_STATE" != "Online" ]]; then
  echo "SSM PingStatus is '$SSM_STATE' (expected Online). Fix SSM before running." >&2
  exit 1
fi

CUR_SIZE=$(aws ec2 describe-volumes --region "$REGION" --volume-ids "$VOLUME_ID" \
  --query 'Volumes[0].Size' --output text)

echo "Instance=$INSTANCE_ID region=$REGION az=$AZ rootDevice=$ROOT_DEV volume=$VOLUME_ID currentSizeGiB=$CUR_SIZE targetGiB=$TARGET_GIB"

if [[ "$CUR_SIZE" -ge "$TARGET_GIB" ]]; then
  echo "Volume already >= ${TARGET_GIB} GiB. Running grow/verify via SSM only (no snapshot, no modify-volume)."
else
  if [[ -n "$SKIP_SNAPSHOT_CONFIRM" ]]; then
    if [[ "$SKIP_SNAPSHOT_CONFIRM" != "I_ACCEPT_NO_SNAPSHOT" ]]; then
      echo "--skip-snapshot requires exact token: I_ACCEPT_NO_SNAPSHOT" >&2
      exit 1
    fi
    echo "WARNING: proceeding without snapshot (--skip-snapshot). There is no rollback snapshot for this resize."
  elif [[ -n "$EXISTING_SNAPSHOT_ID" ]]; then
    SNAP_ID="$EXISTING_SNAPSHOT_ID"
    echo "Using existing snapshot $SNAP_ID (skipping create-snapshot)."
    wait_for_snapshot_completed "$SNAP_ID"
    print_snapshot_recovery "$SNAP_ID"
  else
    SNAP_DESC="pre-resize-root instance=${INSTANCE_ID} vol=${VOLUME_ID} target=${TARGET_GIB}GiB"
    SNAP_ID=$(aws ec2 create-snapshot --region "$REGION" --volume-id "$VOLUME_ID" \
      --description "$SNAP_DESC" \
      --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=pre-resize-root},{Key=InstanceId,Value=$INSTANCE_ID},{Key=VolumeId,Value=$VOLUME_ID},{Key=TargetGib,Value=$TARGET_GIB}]" \
      --query SnapshotId --output text)
    echo "SnapshotId=$SNAP_ID"
    wait_for_snapshot_completed "$SNAP_ID"
    print_snapshot_recovery "$SNAP_ID"
  fi

  echo "Modifying volume to ${TARGET_GIB} GiB..."
  aws ec2 modify-volume --region "$REGION" --volume-id "$VOLUME_ID" --size "$TARGET_GIB" --output text

  echo "Waiting for volume modification to complete..."
  wait_i=0
  wait_ok=0
  while [[ "$wait_i" -lt 180 ]]; do
    MOD=$(aws ec2 describe-volumes-modifications --region "$REGION" --volume-ids "$VOLUME_ID" \
      --query 'VolumesModifications[0].ModificationState' --output text 2>/dev/null || echo "")
    SZ=$(aws ec2 describe-volumes --region "$REGION" --volume-ids "$VOLUME_ID" \
      --query 'Volumes[0].Size' --output text)
    # AWS: extend the OS only once modification is optimizing or completed (size takes effect in optimizing).
    # See https://docs.aws.amazon.com/ebs/latest/userguide/recognize-expanded-volume-linux.html
    if [[ "$SZ" == "$TARGET_GIB" ]]; then
      if [[ -z "$MOD" || "$MOD" == "None" || "$MOD" == "completed" || "$MOD" == "optimizing" ]]; then
        if [[ "$MOD" == "optimizing" ]]; then
          echo "Volume size is ${TARGET_GIB} GiB; state=optimizing (continuing to grow filesystem)."
        fi
        wait_ok=1
        break
      fi
    fi
    if [[ "$MOD" == "failed" ]]; then
      echo "Volume modification failed." >&2
      exit 1
    fi
    wait_i=$((wait_i + 1))
    sleep 5
  done
  if [[ "$wait_ok" -ne 1 ]]; then
    echo "Timed out waiting for volume modification (last size reported: ${SZ:-unknown})." >&2
    exit 1
  fi
fi

SSM_BODY=$(mktemp)
cat > "$SSM_BODY" <<'SSMSCRIPT'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# growpart uses a temp dir; avoid small tmpfs /tmp on tight disks (AWS troubleshooting).
export TMPDIR=/var/tmp
if ! command -v growpart >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq cloud-guest-utils
fi
ROOT=$(findmnt -n -o SOURCE /)
ROOT=$(readlink -f "$ROOT")
# Do not use lsblk PARTNUM: some images (older util-linux) reject that column ("unknown column: PARTNUM").
parent=$(lsblk -dn -o PKNAME "$ROOT" 2>/dev/null || true)
if [[ -z "$parent" ]]; then
  echo "Could not read PKNAME for $ROOT" >&2
  lsblk
  exit 1
fi
DISK="/dev/$parent"
bn=$(basename "$ROOT")
PARTNUM=""
if [[ "$bn" =~ ^${parent}p([0-9]+)$ ]]; then
  PARTNUM="${BASH_REMATCH[1]}"
elif [[ "$bn" =~ ^${parent}([0-9]+)$ ]]; then
  PARTNUM="${BASH_REMATCH[1]}"
fi
if [[ -z "$PARTNUM" || "$PARTNUM" == "0" ]]; then
  echo "Could not derive partition number from root=$ROOT (PKNAME=$parent basename=$bn)" >&2
  lsblk
  exit 1
fi
echo "Growing partition: disk=$DISK part=$PARTNUM root=$ROOT"
set +e
gp_out=$(growpart "$DISK" "$PARTNUM" 2>&1)
gp_rc=$?
set -e
echo "$gp_out"
if [[ "$gp_rc" -ne 0 ]]; then
  if echo "$gp_out" | grep -qi 'NOCHANGE'; then
    echo "growpart: partition already fills the disk (ok)."
  else
    exit "$gp_rc"
  fi
fi
resize2fs "$ROOT"
echo "=== df -h / ==="
df -h /
echo "=== lsblk ==="
lsblk
SSMSCRIPT

PARAMS=$(mktemp)
jq -n --rawfile s "$SSM_BODY" '{commands:[$s]}' > "$PARAMS"
rm -f "$SSM_BODY"

echo "Sending SSM grow + resize2fs..."
CMD_ID=$(aws ssm send-command --region "$REGION" \
  --document-name AWS-RunShellScript \
  --instance-ids "$INSTANCE_ID" \
  --parameters "file://$PARAMS" \
  --timeout-seconds 600 \
  --comment "resize root volume + ext4" \
  --query Command.CommandId --output text)
rm -f "$PARAMS"

aws ssm wait command-executed --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID"
STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query Status --output text)
OUT=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query StandardOutputContent --output text)
ERR=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query StandardErrorContent --output text)

echo "$OUT"
if [[ -n "${ERR:-}" ]]; then
  echo "--- stderr ---" >&2
  echo "$ERR" >&2
fi

if [[ "$STATUS" != "Success" ]]; then
  echo "SSM command status=$STATUS" >&2
  exit 1
fi

echo "Done. CommandId=$CMD_ID"
