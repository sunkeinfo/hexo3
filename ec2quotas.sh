#!/bin/bash

# ==============================================================================
# 脚本: get_core_quotas_v8_cn.sh
# 描述: 仅查询两个关键 EC2 vCPU 配额，并只显示其当前应用的数值。
# 依赖: aws-cli, jq
# 版本: 8.0 (极简最终版)
# ==============================================================================

# --- 配置 ---
AWS_REGION="us-east-1"
SERVICE_CODE="ec2"
# 1. Spot 实例请求配额
PRIMARY_QUOTA_NAME="All Standard (A, C, D, H, I, M, R, T, Z) Spot Instance Requests"
# 2. 按需标准实例配额
SECONDARY_QUOTA_NAME="Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances"

# --- 依赖检查 ---
if ! command -v aws &> /dev/null; then
    echo "错误: 未找到 aws-cli 命令。请先安装和配置 AWS CLI。" >&2
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "错误: 未找到 jq 命令。请先安装 jq。" >&2
    exit 1
fi

# --- 核心逻辑 ---
echo "正在查询关键 EC2 配额..."
aws_output=$(aws service-quotas list-service-quotas --service-code "$SERVICE_CODE" --region "$AWS_REGION" 2>&1)
if [ $? -ne 0 ]; then
    echo "错误: AWS CLI 命令执行失败。" >&2
    echo "AWS 返回的错误信息: $aws_output" >&2
    exit 1
fi

# --- 解析和输出 ---
echo "--------------------------------------------------"

# 使用 jq 直接筛选出我们需要的两个配额
specific_quotas=$(echo "$aws_output" | jq -c \
    --arg primary "$PRIMARY_QUOTA_NAME" \
    --arg secondary "$SECONDARY_QUOTA_NAME" \
    '.Quotas[] | select(.QuotaName == $primary or .QuotaName == $secondary)')

# 检查是否找到了任何一个我们关心的配额
if [[ -z "$specific_quotas" ]]; then
    echo "错误: 未能找到任何指定的关键配额。"
    exit 1
fi

found_primary=false
found_secondary=false

# 循环处理找到的结果
echo "$specific_quotas" | while read -r quota_json; do
    quota_name=$(echo "$quota_json" | jq -r '.QuotaName')
    applied_value=$(echo "$quota_json" | jq -r '.Value')

    # 将数值转为整数 (例如 64.0 -> 64)
    applied_value_display=$(printf "%.0f" "$applied_value")

    # (*** 关键修改：单行输出，只显示当前值 ***)
    if [[ "$quota_name" == "$PRIMARY_QUOTA_NAME" ]]; then
        echo "✅ Spot 实例请求配额: ${applied_value_display} vCPUs"
        found_primary=true
    elif [[ "$quota_name" == "$SECONDARY_QUOTA_NAME" ]]; then
        echo "✅ 按需实例配额: ${applied_value_display} vCPUs"
        found_secondary=true
    fi
done

# --- 最终检查 ---
if [ "$found_primary" = false ]; then
    echo "⚠️  注意: 未找到 Spot 实例请求配额 (${PRIMARY_QUOTA_NAME})。"
fi
if [ "$found_secondary" = false ]; then
    echo "⚠️  注意: 未找到按需实例配额 (${SECONDARY_QUOTA_NAME})。"
fi

echo "--------------------------------------------------"
exit 0
