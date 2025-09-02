#!/bin/bash

# ==============================================================================
# AWS Elastic IP Association Script (Generic Version)
#
# Description: This script associates a specific Elastic IP with an EC2 instance
#              for a short duration (10 seconds) and then disassociates it.
#              It accepts region, IP, and instance ID as command-line arguments.
#
# Usage: 
# curl -sS "URL_TO_THIS_RAW_SCRIPT" | bash -s -- <region> <ip-address> <instance-id>
#
# Example:
# curl -sS "URL" | bash -s -- us-east-2 3.149.176.94 i-094ccfdca8be8c80f
# ==============================================================================

# --- 函数：打印格式化信息 ---
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- 参数验证 ---
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  log_message "错误：缺少必要的参数。"
  log_message "用法: bash -s -- <region> <ip-address> <instance-id>"
  exit 1
fi

# --- 从命令行参数读取配置变量 ---
REGION="$1"
EIP="$2"
INSTANCE_ID="$3"

# --- 脚本主逻辑 ---

log_message "启动弹性IP管理脚本，区域: $REGION..."
log_message "=========================================================="
log_message "目标IP: ${EIP}"
log_message "目标实例ID: ${INSTANCE_ID}"

# 1. 获取公网IP的 Allocation ID
log_message "正在为IP ${EIP} 查找 Allocation ID..."
# 将错误输出重定向到 /dev/null 以避免在找不到时显示不必要的AWS错误信息
ALLOCATION_ID=$(aws ec2 describe-addresses --region $REGION --public-ips $EIP --query "Addresses[0].AllocationId" --output text 2> /dev/null)

# 检查是否成功找到 Allocation ID
if [ -z "$ALLOCATION_ID" ]; then
  log_message "错误: 无法在区域 ${REGION} 中找到IP ${EIP} 的 Allocation ID。"
  log_message "请检查IP地址是否正确，以及它是否属于您在该区域的AWS账户。"
  exit 1
fi
log_message "成功找到 Allocation ID: $ALLOCATION_ID"

# 2. 将弹性IP关联到EC2实例
log_message "正在将IP ${EIP} 关联到实例 ${INSTANCE_ID}..."
ASSOCIATE_OUTPUT=$(aws ec2 associate-address --region $REGION --instance-id $INSTANCE_ID --allocation-id $ALLOCATION_ID --output json)

# 检查关联命令是否成功执行
if [ $? -ne 0 ]; then
    log_message "错误: 关联弹性IP失败。脚本中止。"
    # AWS CLI 已经打印了详细错误，所以我们直接退出
    exit 1
fi

# 从返回的JSON中提取新的 Association ID
ASSOCIATION_ID=$(echo $ASSOCIATE_OUTPUT | grep -o 'eipassoc-[a-zA-Z0-9]*')
if [ -z "$ASSOCIATION_ID" ]; then
    log_message "错误: 无法从输出中解析出 Association ID。请检查AWS CLI的输出。"
    exit 1
fi
log_message "关联命令已提交。新的 Association ID 是: $ASSOCIATION_ID"

# 3. 等待10秒
log_message "等待10秒..."
sleep 10

# 4. 解除弹性IP与实例的关联
log_message "正在解除IP ${EIP} 的关联 (Association ID: $ASSOCIATION_ID)..."
aws ec2 disassociate-address --region $REGION --association-id $ASSOCIATION_ID

if [ $? -eq 0 ]; then
    log_message "成功解除弹性IP的关联。"
else
    log_message "警告: 解除关联的命令失败。请手动检查实例状态。"
fi

log_message "=========================================================="
log_message "脚本执行完毕。"
