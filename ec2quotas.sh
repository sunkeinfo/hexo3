#!/bin/bash

# ==============================================================================
# Script: get_all_ec2_vcpu_quotas_v3.sh
# Description: Checks all AWS EC2 vCPU quotas, prioritizing the main "Running
#              On-Demand instances" quota, and lists all other specific
#              instance family quotas as well.
# Dependencies: aws-cli, jq
# Version: 3.0
# ==============================================================================

# --- Configuration ---
# 您可以根据需要修改区域
AWS_REGION="us-east-1"
# 服务代码保持不变
SERVICE_CODE="ec2"

# --- 依赖检查 ---

# 检查 aws-cli 是否已安装
if ! command -v aws &> /dev/null; then
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
echo "在 ${AWS_REGION} 区域找到的 EC2 vCPU 配额如下:"
echo "--------------------------------------------------"

# (*** 这是最终修改的部分 ***)
# 使用更精准的 jq 逻辑来捕获所有相关的 vCPU 配额。
# AWS API 并不提供一个名为 "All Running Instances" 的单一配额。
# 相反，它按实例类型（如 Standard, F, G, P 等）提供多个配额。
# 此脚本的目标是显示所有这些独立的配额。
# 过滤器 'contains("Running") and contains("instance")' 是捕获这些配额的最可靠方法。

filtered_quotas=$(echo "$aws_output" | jq -c '.Quotas[] | select(.QuotaName | contains("Running") and contains("instance"))')

# 检查筛选结果是否为空
if [[ -z "$filtered_quotas" ]]; then
    echo "未能在 ${AWS_REGION} 区域找到任何与正在运行的实例相关的 vCPU 配额。"
    echo "这可能是权限问题或该区域确实没有此类配额。请检查 AWS 返回的原始数据:"
    echo "$aws_output"
    exit 0
fi

# 标记是否找到了最重要的那个配额
found_main_quota=false

# 循环输出筛选出的配额
echo "$filtered_quotas" | while read -r quota_json; do
    quota_name=$(echo "$quota_json" | jq -r '.QuotaName')
    quota_value=$(echo "$quota_json" | jq -r '.Value')

    # 检查值是否有效
    if [[ -z "$quota_value" || "$quota_value" == "null" ]]; then
        echo "警告: 未能为配额 '${quota_name}' 提取到有效值。" >&2
        continue
    fi

    # 特别高亮显示最重要的总配额
    if [[ "$quota_name" == "Running On-Demand instances" ]]; then
        echo "✅ 主要配额: \"${quota_name}\", 当前限制是 ${quota_value} vCPUs。"
        found_main_quota=true
    else
        # 打印其他所有分类配额
        echo "   - 分类配额: \"${quota_name}\", 当前限制是 ${quota_value} vCPUs。"
    fi
done

# 如果循环结束后仍未找到总配额，给出一个提示
if [ "$found_main_quota" = false ]; then
    echo "--------------------------------------------------"
    echo "注意: 未找到名为 'Running On-Demand instances' 的主要总配额。"
    echo "上面列出的是按实例家族分类的所有可用配额。"
fi


exit 0
