#!/bin/bash

# ==============================================================================
# 脚本: get_all_ec2_vcpu_quotas_v5_cn.sh
# 描述: 检查所有 AWS EC2 vCPU 配额，正确识别并优先显示关键配额，
#       同时列出当前账户应用的配额值和 AWS 的默认值。
# 依赖: aws-cli, jq
# 版本: 5.0 (中文输出)
# ==============================================================================

# --- 配置 ---
# 您可以根据需要修改区域
AWS_REGION="us-east-1"
# 服务代码保持不变
SERVICE_CODE="ec2"
# (*** 根据您的反馈，定义了需要高亮显示的主要配额名称 ***)
MAIN_QUOTA_NAME="All Standard (A, C, D, H, I, M, R, T, Z) Spot Instance Requests"
SECONDARY_QUOTA_NAME="Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances"

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
echo "在 ${AWS_REGION} 区域找到的 EC2 vCPU 配额如下:"
echo "--------------------------------------------------"

# 使用 jq 筛选出所有与正在运行的实例或 Spot 请求相关的配额
# 过滤逻辑：名称中包含 "instance" 以及 ("Running" 或 "Requests")
filtered_quotas=$(echo "$aws_output" | jq -c '.Quotas[] | select(.QuotaName | (contains("Running") or contains("Requests")) and contains("instance"))')

# 检查筛选结果是否为空
if [[ -z "$filtered_quotas" ]]; then
    echo "未能在 ${AWS_REGION} 区域找到任何与实例相关的 vCPU 配额。"
    echo "这可能是权限问题。以下是 AWS 返回的原始数据:"
    echo "$aws_output"
    exit 0
fi

found_main_quota=false

# 循环遍历所有筛选出的配额
echo "$filtered_quotas" | while read -r quota_json; do
    quota_name=$(echo "$quota_json" | jq -r '.QuotaName')
    applied_value=$(echo "$quota_json" | jq -r '.Value')
    # (*** 新增功能 ***) 从 JSON 中提取 AWS 默认值
    default_value=$(echo "$quota_json" | jq -r '.DefaultValue')

    # 如果配额值无效，则跳过
    if [[ -z "$applied_value" || "$applied_value" == "null" ]]; then
        continue
    fi

    # (*** 新增功能 ***) 格式化输出，使其包含默认值
    output_line="\"${quota_name}\"\n   - 当前应用值: ${applied_value} vCPUs (AWS 默认值: ${default_value} vCPUs)"

    # 高亮显示您指定的两个主要配额
    if [[ "$quota_name" == "$MAIN_QUOTA_NAME" || "$quota_name" == "$SECONDARY_QUOTA_NAME" ]]; then
        echo -e "✅ 主要配额: ${output_line}"
        found_main_quota=true
    else
        echo -e "   - 其他配额: ${output_line}"
    fi
done

# 如果循环结束后仍未找到指定的总配额，给出一个明确的提示
if [ "$found_main_quota" = false ]; then
    echo "--------------------------------------------------"
    echo "注意: 未找到任何已定义的关键配额 (例如 '${MAIN_QUOTA_NAME}')。"
fi

exit 0
