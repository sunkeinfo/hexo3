#!/bin/bash

# -----------------------------------------------------------------------------
# Script: update_aws_address_auto.sh
# Description: Automatically updates an AWS account's contact address without
#              user confirmation. It fetches the current contact info,
#              modifies only the State, Postal Code, and Country, then
#              submits the full updated record immediately.
# Dependencies: aws-cli, jq
# -----------------------------------------------------------------------------

# 如果任何命令失败，则立即退出
set -e
set -o pipefail

# --- 依赖检查 ---
# 检查 aws-cli 和 jq 是否已安装
command -v aws >/dev/null 2>&1 || { echo >&2 "错误：找不到 'aws' 命令。请先安装 AWS CLI。"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "错误：找不到 'jq' 命令。请先安装 jq (一个命令行 JSON 处理器)。"; exit 1; }

# --- 定义要修改的值 ---
NEW_STATE="CA"
NEW_POSTAL_CODE="90000"
NEW_COUNTRY_CODE="US"

# --- 执行操作 ---
echo "第 1 步：正在从 AWS 获取当前的联系信息..."

# 获取当前的联系信息
CURRENT_INFO=$(aws account get-contact-information --output json)
if [ -z "$CURRENT_INFO" ]; then
    echo "错误：无法从 AWS 获取联系信息。请检查您的 AWS CLI 配置和权限。"
    exit 1
fi

# 提取核心的 ContactInformation 对象
CONTACT_INFO_JSON=$(echo "$CURRENT_INFO" | jq '.ContactInformation')

echo "获取成功！"
echo ""

echo "第 2 步：正在准备要更新的数据..."
echo "将应用以下更改："
echo "--------------------------------------------------"
echo "  State/Region:     将更改为 -> $NEW_STATE"
echo "  Postal Code:      将更改为 -> $NEW_POSTAL_CODE"
echo "  Country Code:     将更改为 -> $NEW_COUNTRY_CODE"
echo "--------------------------------------------------"
echo "所有其他信息（姓名、地址、城市、电话等）将保持不变。"
echo ""

# 使用 jq 修改指定的字段，同时保留所有其他字段不变
UPDATED_INFO_JSON=$(echo "$CONTACT_INFO_JSON" | jq \
  --arg state "$NEW_STATE" \
  --arg postal_code "$NEW_POSTAL_CODE" \
  --arg country_code "$NEW_COUNTRY_CODE" \
  '.StateOrRegion = $state | .PostalCode = $postal_code | .CountryCode = $country_code'
)

echo "第 3 步：正在将更新后的信息自动提交到 AWS..."

# 执行 AWS CLI 命令来推送更新后的完整联系信息
aws account put-contact-information --contact-information "$UPDATED_INFO_JSON"

echo "✅ 操作已自动完成！"
echo "请登录 AWS 管理控制台以验证更改。"
