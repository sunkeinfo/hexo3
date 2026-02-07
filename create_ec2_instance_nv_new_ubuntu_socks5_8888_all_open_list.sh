#!/bin/bash

# 实例和区域配置
INSTANCE_NAME="my-ubuntu-ec2"
REGION="us-east-1"  # 请根据您的实际需求修改 AWS 区域
INSTANCE_TYPE="t2.nano" # 实例类型，例如 t2.nano, t3.micro 等

# 安全组配置
SECURITY_GROUP_NAME="allow-all-sg"

echo "正在获取或创建安全组..."
# 尝试获取已有的安全组 ID
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --group-names "$SECURITY_GROUP_NAME" \
  --region "$REGION" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

# 如果找不到安全组，则创建新的
if [ "$SECURITY_GROUP_ID" == "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
  echo "正在创建新的安全组: $SECURITY_GROUP_NAME ..."
  SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "Allow all traffic" \
    --region "$REGION" \
    --query 'GroupId' \
    --output text)
  
  # 为新创建的安全组开放所有入站端口
  echo "正在为安全组 $SECURITY_GROUP_ID 开放所有端口 (0-65535)..."
  aws ec2 authorize-security-group-ingress \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol all \
    --port 0-65535 \
    --cidr 0.0.0.0/0 \
    --region "$REGION"
  echo "已创建安全组: $SECURITY_GROUP_ID"
else
  echo "正在使用现有的安全组: $SECURITY_GROUP_ID"
fi

echo "正在获取 Ubuntu 22.04 AMI ID..."
# 使用您之前成功找到的 Ubuntu 22.04 AMI ID
# AMI_ID=$(aws ec2 describe-images \
#   --region "$REGION" \
#   --owners 099720109477 \
#   --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*' 'Name=state,Values=available' \
#   --query 'reverse(sort_by(Images, &CreationDate))[0].ImageId' \
#   --output text)

# 直接使用找到的 AMI ID
AMI_ID="ami-0a03ce9a6035af491" 
echo "使用 AMI ID: $AMI_ID"

# 检查 AMI ID 是否有效
if [ "$AMI_ID" == "None" ] || [ -z "$AMI_ID" ]; then
  echo "错误：无法找到 Ubuntu 22.04 AMI ID。请检查您的 AWS 区域配置或手动查找。"
  exit 1
fi

echo "正在创建 EC2 实例 '$INSTANCE_NAME' ..."
# 启动 EC2 实例
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "$INSTANCE_TYPE" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --user-data "#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
curl -sL https://hosting.sunke.info/files/socks5_safe.sh | bash" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --region "$REGION" \
  --query 'Instances[0].InstanceId' \
  --output text)

# 检查实例是否创建成功
if [ -z "$INSTANCE_ID" ]; then
  echo "错误：创建 EC2 实例失败。"
  exit 1
fi

echo "实例 '$INSTANCE_NAME' 已创建，实例 ID: $INSTANCE_ID"

echo "正在等待实例进入 'running' 状态..."
# 等待实例进入运行状态
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

echo "正在获取实例的公网 IP 地址..."
# 获取实例的公网 IP 地址
IP_ADDRESS=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "EC2 实例 '$INSTANCE_NAME' 创建成功！"
echo "实例 ID: $INSTANCE_ID"
echo "IPv4 地址: $IP_ADDRESS"
echo "您可以使用 SSH 客户端连接到: ssh ubuntu@$IP_ADDRESS"
