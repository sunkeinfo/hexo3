#!/bin/bash

INSTANCE_NAME="my-ubuntu-ec2"
REGION="us-east-1"  # 请根据您的实际需求修改区域
INSTANCE_TYPE="t2.nano"

SECURITY_GROUP_NAME="allow-all-sg"

echo "正在获取或创建安全组..."
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --group-names "$SECURITY_GROUP_NAME" \
  --region "$REGION" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

if [ "$SECURITY_GROUP_ID" == "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
  echo "正在创建新的安全组..."
  SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "Allow all traffic" \
    --region "$REGION" \
    --query 'GroupId' \
    --output text)
  
  echo "正在为安全组开放所有端口..."
  aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol all \
    --port 0-65535 \
    --cidr 0.0.0.0/0 \
    --region "$REGION"
else
  echo "正在使用现有安全组: $SECURITY_GROUP_ID"
fi

echo "正在获取 Ubuntu 24.04 AMI ID..."
# 修改了 AMI 的查找过滤器，以指向 Ubuntu 24.04 (Noble)
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text \
  --region "$REGION")

if [ "$AMI_ID" == "None" ] || [ -z "$AMI_ID" ]; then
  echo "错误：无法找到 Ubuntu 24.04 AMI"
  # 尝试使用 SSM Parameter Store 获取 AMI ID
  echo "尝试通过 SSM Parameter Store 获取 Ubuntu 24.04 AMI ID..."
  AMI_ID=$(aws ssm get-parameters \
    --names /aws/service/canonical/ubuntu/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query "Parameters[0].Value" \
    --output text \
    --region "$REGION")

  if [ "$AMI_ID" == "None" ] || [ -z "$AMI_ID" ]; then
    echo "错误：通过 SSM Parameter Store 也无法找到 Ubuntu 24.04 AMI"
    exit 1
  fi
  echo "通过 SSM Parameter Store 使用 AMI: $AMI_ID"
else
  echo "使用 AMI: $AMI_ID"
fi

echo "正在创建 EC2 实例..."
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
  echo "错误：创建实例失败"
  exit 1
fi

echo "实例 ID: $INSTANCE_ID"

echo "正在等待实例运行..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

echo "正在获取实例 IP 地址..."
IP_ADDRESS=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "EC2 实例 '$INSTANCE_NAME' 已成功创建！"
echo "实例 ID: $INSTANCE_ID"
echo "IPv4 地址: $IP_ADDRESS"
