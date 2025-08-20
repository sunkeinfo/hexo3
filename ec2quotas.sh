#!/bin/bash

# ==============================================================================
# Script: get_ec2_vcpu_quota.sh
# Description: Checks the AWS EC2 vCPU quota for "Running On-Demand Standard
#              instances" in the us-east-1 region and returns a human-readable sentence.
# Dependencies: aws-cli, jq
# ==============================================================================

# --- Configuration ---
# 您可以根据需要修改区域
AWS_REGION="us-east-1"
# 要查询的配额的确切名称
QUOTA_NAME="Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances"
SERVICE_CODE="ec2"

# --- 依赖检查 ---

# 检查 aws-cli 是否已安装
if ! command -v aws &> /dev/null; then
    # 将错误信息输出到 stderr
    echo "错误: 未找到 aws-cli 命令。请先安装和配置 AWS CLI。" >&2
    exit 1
fi

# 检查 jq 是否已安装
if ! command -v jq &> /dev/null; then
    echo "错误: 未找到 jq 命令。jq 用于解析结果，请先安装 (例如: 'sudo apt install jq' 或 'brew install jq')。" >&2
    exit 1
fi

# --- 核心逻辑 ---

# 执行 AWS CLI 命令，并将 stderr 重定向以捕获可能的错误信息
aws_output=$(aws service-quotas list-service-quotas \
    --service-code "$SERVICE_CODE" \
    --region "$AWS_REGION" \
    --query "Quotas[?QuotaName == '$QUOTA_NAME']" 2>&1)

# 检查上一条命令的退出状态码，判断是否执行成功
if [ $? -ne 0 ]; then
    echo "错误: AWS CLI 命令执行失败。" >&2
    echo "AWS 返回的错误信息: $aws_output" >&2
    exit 1
fi

# 使用 jq 解析 JSON 输出，提取配额值。-r 选项可以移除结果中的双引号。
quota_value=$(echo "$aws_output" | jq -r '.[0].Value')

# 检查是否成功提取到值
if [[ -z "$quota_value" || "$quota_value" == "null" ]]; then
    echo "错误: 未能在 AWS 的返回结果中找到指定的配额 '$QUOTA_NAME'。" >&2
    echo "完整的 AWS 返回内容: $aws_output" >&2
    exit 1
fi

# --- 输出结果 ---

# (*** 这是修改过的部分 ***)
# 成功后，打印格式化的句子，并指明单位是 vCPU
echo "你的 ${AWS_REGION} 区域按需实例配额是 ${quota_value} vCPUs。"

exit 0
