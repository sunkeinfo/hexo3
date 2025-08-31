#!/bin/bash

# ==============================================================================
# Script: get_all_ec2_vcpu_quotas.sh
# Description: Checks all AWS EC2 vCPU quotas for running instances
#              in the specified region and returns human-readable sentences.
# Dependencies: aws-cli, jq
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
# 注意：这里移除了原有的 --query 参数，以便获取完整的列表
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

# 使用 jq 解析 JSON，筛选出所有与正在运行的实例相关的 vCPU 配额，并循环输出
# - 我们选择包含 "Running" 和 "instances" 并且单位是 "vCPU" 的配额
# - 使用 `jq -c` 来输出紧凑的、每行一个的 JSON 对象，便于 `while` 循环读取
echo "--------------------------------------------------"
echo "在 ${AWS_REGION} 区域找到的实例 vCPU 配额如下:"
echo "--------------------------------------------------"

echo "$aws_output" | jq -c '.Quotas[] | select(.QuotaName | contains("Running") and contains("instances")) | select(.Unit == "Count")' | while read -r quota_json; do
    # 从每个 JSON 对象中提取配额名称和值
    quota_name=$(echo "$quota_json" | jq -r '.QuotaName')
    quota_value=$(echo "$quota_json" | jq -r '.Value')

    # 检查是否成功提取到值
    if [[ -z "$quota_value" || "$quota_value" == "null" ]]; then
        echo "警告: 未能为配额 '${quota_name}' 提取到有效值。" >&2
    else
        # 打印格式化的句子
        # 注意：AWS 返回的这类配额单位是 "Count"，但实际上代表 vCPU 的数量
        echo "配额: \"${quota_name}\", 当前限制是 ${quota_value} vCPUs。"
    fi
done

# 检查是否输出了任何配额，如果没有，则给出提示
if ! echo "$aws_output" | jq -e '.Quotas[] | select(.QuotaName | contains("Running") and contains("instances"))' > /dev/null; then
    echo "未能在 ${AWS_REGION} 区域找到任何与正在运行的实例相关的 vCPU 配额。"
    echo "请检查 AWS 返回的原始数据:"
    echo "$aws_output"
fi

exit 0
