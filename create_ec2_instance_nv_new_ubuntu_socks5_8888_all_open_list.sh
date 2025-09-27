#!/bin/bash

INSTANCE_NAME="my-ubuntu-ec2"
REGION="us-east-1"
INSTANCE_TYPE="t2.nano"

SECURITY_GROUP_NAME="allow-all-sg"

echo "Getting or creating security group..."
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --group-names "$SECURITY_GROUP_NAME" \
  --region "$REGION" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

if [ "$SECURITY_GROUP_ID" == "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
  echo "Creating new security group..."
  SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "Allow all traffic" \
    --region "$REGION" \
    --query 'GroupId' \
    --output text)
  
  echo "Opening all ports in security group..."
  aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol all \
    --port 0-65535 \
    --cidr 0.0.0.0/0 \
    --region "$REGION"
else
  echo "Using existing security group: $SECURITY_GROUP_ID"
fi

echo "Getting Ubuntu 24.04 AMI ID..."
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text \
  --region "$REGION")

if [ "$AMI_ID" == "None" ] || [ -z "$AMI_ID" ]; then
  echo "Error: Could not find Ubuntu AMI"
  exit 1
fi

echo "Using AMI: $AMI_ID"

echo "Creating EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "$INSTANCE_TYPE" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --user-data $'#!/bin/bash\nbash <(curl -sL https://hosting.sunke.info/files/ss5.sh)' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --region "$REGION" \
  --query 'Instances[0].InstanceId' \
  --output text)

if [ -z "$INSTANCE_ID" ]; then
  echo "Error: Failed to create instance"
  exit 1
fi

echo "Instance ID: $INSTANCE_ID"

echo "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

echo "Getting instance IP address..."
IP_ADDRESS=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "EC2 instance '$INSTANCE_NAME' created successfully!"
echo "Instance ID: $INSTANCE_ID"
echo "IPv4 address: $IP_ADDRESS"
