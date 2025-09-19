#!/bin/bash

# -----------------------------------------------------------------------------
# 脚本: update_and_delete_tax_smart.sh
# 描述: 自动更新AWS账户联系地址，然后智能地删除税务信息，并汇报详细结果。
#
# !!! 重要前提 !!!
# 此脚本必须在 AWS `us-east-1` (弗吉尼亚北部) 区域运行。
# 如果您在 CloudShell 中使用，请务必先将区域切换到 us-east-1。
# -----------------------------------------------------------------------------

# 如果任何命令失败（除了我们手动处理的错误），则立即退出
set -e
set -o pipefail

# --- 依赖检查 ---
command -v aws >/dev/null 2>&1 || { echo >&2 "错误：找不到 'aws' 命令。请先安装 AWS CLI。"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "错误：找不到 'jq' 命令。请先安装 jq。"; exit 1; }

# --- 第 1-3 步：更新联系信息 ---
echo "第 1-3 步：正在更新联系地址..."
CURRENT_INFO=$(aws account get-contact-information)
CONTACT_INFO_JSON=$(echo "$CURRENT_INFO" | jq '.ContactInformation')
UPDATED_INFO_JSON=$(echo "$CONTACT_INFO_JSON" | jq \
  '.StateOrRegion = "CA" | .PostalCode = "90000" | .CountryCode = "US"'
)
aws account put-contact-information --contact-information "$UPDATED_INFO_JSON"
echo "✅ 联系地址更新已自动完成！"
echo ""
echo "--------------------------------------------------"
echo ""

# --- 第 4 步：智能执行删除命令并汇报结果 ---
echo "第 4 步：正在执行删除税务信息命令并汇报结果..."

# 执行命令，同时捕获其所有输出（包括正常和错误信息）
# `2>&1` 是关键，它将错误流合并到标准输出流，以便下面可以完整捕获
command_output=$(aws taxsettings delete-tax-registration 2>&1)
exit_code=$? # 立刻获取刚刚执行的aws命令的退出码 (0代表成功，非0代表失败)

# 根据退出码判断并汇报结果
if [ $exit_code -eq 0 ]; then
    # 退出码为0，表示成功
    echo "✅ 操作成功：删除税务信息的命令已成功执行。"
    # AWS官方说明成功时无输出，但我们仍然检查一下以防万一
    if [ -n "$command_output" ]; then
        echo "AWS 返回了如下信息："
        echo "$command_output"
    fi
else
    # 退出码非0，表示失败
    echo "❌ 操作失败：删除税务信息时遇到错误。"
    echo "-------------------- AWS CLI 返回的原始结果 --------------------"
    echo "$command_output"
    echo "-----------------------------------------------------------------"
    echo "请检查以上由AWS直接返回的错误信息以定位问题。常见原因包括："
    echo "  1. 权限不足：请确保您的IAM用户/角色拥有 'tax:DeleteTaxRegistration' 权限。"
    echo "  2. 账户中无税务信息：如果错误信息包含 'TaxRegistrationNotFoundException'，说明原本就没有税务信息可删，可以安全地忽略此错误。"
    echo "  3. 运行区域错误：请再次确认您当前是否在 'us-east-1' 区域。"
fi

echo ""
echo "脚本执行完毕。"
