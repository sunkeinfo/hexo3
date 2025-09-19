#!/bin/bash

# -----------------------------------------------------------------------------
# 脚本: update_aws_account_auto.sh
# 描述: 自动更新AWS账户的联系地址，并自动删除所有税务信息。
#       此脚本不进行任何确认，请谨慎使用。
# 依赖: aws-cli, jq
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
echo "  州/省/地区:     将更改为 -> $NEW_STATE"
echo "  邮政编码:         将更改为 -> $NEW_POSTAL_CODE"
echo "  国家代码:         将更改为 -> $NEW_COUNTRY_CODE"
echo "--------------------------------------------------"
echo "所有其他信息将保持不变。"
echo ""

# 使用 jq 修改指定的字段
UPDATED_INFO_JSON=$(echo "$CONTACT_INFO_JSON" | jq \
  --arg state "$NEW_STATE" \
  --arg postal_code "$NEW_POSTAL_CODE" \
  --arg country_code "$NEW_COUNTRY_CODE" \
  '.StateOrRegion = $state | .PostalCode = $postal_code | .CountryCode = $country_code'
)

echo "第 3 步：正在将更新后的信息自动提交到 AWS..."

# 推送更新后的联系信息
aws account put-contact-information --contact-information "$UPDATED_INFO_JSON"

echo "✅ 联系地址更新已自动完成！"
echo ""
echo "--------------------------------------------------"
echo ""

# --- 新增功能：自动删除税务信息 ---
echo "第 4 步：正在自动删除税务信息..."

# 直接尝试执行删除操作
if aws tax delete-tax-registration; then
    echo "✅ 税务信息已成功删除。"
else
    # 如果命令执行失败（例如，没有税务信息可删或权限不足），会返回非零退出码
    echo "警告：删除税务信息的操作已执行完毕。该警告可能表示账户原本就没有税务信息，或者发生了其他错误。请登录 AWS 管理控制台进行最终核实。"
fi

echo ""
echo "脚本执行完毕。"
