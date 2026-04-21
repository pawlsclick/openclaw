#!/usr/bin/env bash
set -euo pipefail

# Update the OpenClaw EC2 CloudFormation stack from the repo root.
# Defaults match the template in infra/aws/openclaw-ec2.yaml but can be
# overridden via environment variables.

REGION="${REGION:-eu-north-1}"
STACK_NAME="${STACK_NAME:-openclaw-gateway}"
AMI_ID="${AMI_ID:-ami-08798aaab28f7b459}"

echo "Waiting for AMI '${AMI_ID}' to be available (required before stack update)..."
aws ec2 wait image-available --region "$REGION" --image-ids "$AMI_ID"
echo "AMI available."

echo "Updating stack '${STACK_NAME}' in region '${REGION}' with AMI '${AMI_ID}'..."

aws cloudformation update-stack \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --template-body file://infra/aws/openclaw-ec2.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=KeyName,ParameterValue=awspawlclick \
    ParameterKey=InstanceType,ParameterValue=t3.large \
    ParameterKey=VpcId,ParameterValue=vpc-05c0d292bf26d7bd1 \
    ParameterKey=SubnetId,ParameterValue=subnet-0954f659cbd458cca \
    ParameterKey=SecurityGroupId,ParameterValue=sg-06969578c0d2792ef \
    ParameterKey=BootVolumeSizeGb,ParameterValue=80 \
    ParameterKey=AmiId,ParameterValue="$AMI_ID"

echo "Waiting for stack update to complete..."

aws cloudformation wait stack-update-complete \
  --region "$REGION" \
  --stack-name "$STACK_NAME"

echo "Stack update complete."

