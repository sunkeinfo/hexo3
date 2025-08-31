#!/bin/bash

# ==============================================================================
# Script: get_all_ec2_vcpu_quotas_v2.sh
# Description: Checks all AWS EC2 vCPU quotas for running instances
#              in the specified region and returns human-readable sentences.
# Dependencies: aws-cli, jq
# Version: 2.0
# ==============================================================================

# --- Configuration ---
# 您可以根据需要修改区域
AWS_REGION="us-east-1"
# 服务代码保持不变
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

echo "正在从 AWS 获取 ${AWS_REGION} 区域的所有 EC2 服务配额，请稍候..."

# 执行 AWS CLI 命令，获取所有 EC2 服务的配额
aws_output=$(aws service-quotas list-service-quotas \
    --service-code "$SERVICE_CODE" \
    --region "$AWS_REGION" 2>&1)

# 检查上一条命令的退出状态码
if [ $? -ne 0 ]; then
    echo "错误: AWS CLI 命令执行失败。" >&2
    echo "AWS 返回的错误信息: $aws_output" >&2
    exit 1
fi

# --- 解析和输出 ---

echo "--------------------------------------------------"
echo "在 ${AWS_REGION} 区域找到的实例 vCPU 配额如下:"
echo "--------------------------------------------------"

# 使用 jq 解析 JSON，筛选出所有与正在运行的实例相关的 vCPU 配额
# (*** 这是修改过的部分 ***)
# 移除了 'select(.Unit == "Count")' 条件，因为它过于严格，
# vCPU 配额的单位通常是 "None" 而不是 "Count"，导致之前无法正确筛选。
filtered_quotas=$(echo "$aws_output" | jq -c '.Quotas[] | select(.QuotaName | contains("Running") and contains("instances"))')

# 检查筛选结果是否为空
if [[ -z "$filtered_quotas" ]]; then
    echo "未能在 ${AWS_REGION} 区域找到任何与正在运行的实例相关的 vCPU 配额。"
    echo "这可能是权限问题或该区域确实没有此类配额。请检查 AWS 返回的原始数据:"
    echo "$aws_output"
    exit 0
fi

# 循环输出筛选出的配额
echo "$filtered_quotas" | while read -r quota_json; do
    # 从每个 JSON 对象中提取配额名称和值
    quota_name=$(echo "$quota_json" | jq -r '.QuotaName')
    quota_value=$(echo "$quota_json" | jq -r '.Value')

    # 检查是否成功提取到值
    if [[ -z "$quota_value" || "$quota_value" == "null" ]]; then
        echo "警告: 未能为配额 '${quota_name}' 提取到有效值。" >&2
    else
        # 打印格式化的句子
        echo "配额: \"${quota_name}\", 当前限制是 ${quota_value} vCPUs。"
    fi
done

exit 0
