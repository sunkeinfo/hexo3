#!/bin/bash

# -----------------------------------------------------------------------------
# 脚本: update_and_delete_tax_auto.sh
# 描述: 自动更新AWS账户联系地址，然后无条件地尝试删除所有税务信息，
#       并明确返回操作结果。
# 依赖: aws-cli, jq
# -----------------------------------------------------------------------------

# 如果任何命令失败（除了我们手动处理的错误），则立即退出
set -e
set -o pipefail

# --- 依赖检查 ---
command -v aws >/dev/null 2>&1 || { echo >&2 "错误：找不到 'aws' 命令。请先安装 AWS CLI。"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "错误：找不到 'jq' 命令。请先安装 jq。"; exit 1; }

# --- 定义要修改的值 ---
NEW_STATE="CA"
NEW_POSTAL_CODE="90000"
NEW_COUNTRY_CODE="US"

# --- 第 1-3 步：更新联系信息 ---
echo "第 1 步：正在获取当前联系信息..."
CURRENT_INFO=$(aws account get-contact-information --output json)
if [ -z "$CURRENT_INFO" ]; then
    echo "错误：无法从 AWS 获取联系信息。"
    exit 1
fi
CONTACT_INFO_JSON=$(echo "$CURRENT_INFO" | jq '.ContactInformation')
echo "获取成功！"
echo ""

echo "第 2 步：正在准备更新数据..."
UPDATED_INFO_JSON=$(echo "$CONTACT_INFO_JSON" | jq \
  --arg state "$NEW_STATE" \
  --arg postal_code "$NEW_POSTAL_CODE" \
  --arg country_code "$NEW_COUNTRY_CODE" \
  '.StateOrRegion = $state | .PostalCode = $postal_code | .CountryCode = $country_code'
)
echo "数据准备完毕。"
echo ""

echo "第 3 步：正在提交更新后的联系信息..."
aws account put-contact-information --contact-information "$UPDATED_INFO_JSON"
echo "✅ 联系地址更新已自动完成！"
echo ""
echo "--------------------------------------------------"
echo ""

# --- 第 4 步：直接删除税务信息并返回结果 ---
echo "第 4 步：正在直接删除税务信息并报告结果..."

# 设置一个变量来捕获命令的输出和错误信息
# 2>&1 将标准错误（stderr）重定向到标准输出（stdout），以便我们可以捕获所有信息
# || true 确保即使aws命令失败，set -e也不会终止整个脚本
command_output=$(aws tax delete-tax-registration 2>&1)
exit_code=$? # 获取aws命令的退出码

# 检查退出码来判断命令是否成功
if [ $exit_code -eq 0 ]; then
    # 退出码为0，表示成功
    echo "✅ 操作成功：税务信息已成功删除。"
    # 如果成功时有任何输出，也一并打印（通常此命令成功时无输出）
    if [ -n "$command_output" ]; then
        echo "AWS 返回信息："
        echo "$command_output"
    fi
else
    # 退出码非0，表示失败
    echo "❌ 操作失败：删除税务信息时遇到错误。"
    echo "-------------------- AWS CLI 返回的原始结果 --------------------"
    echo "$command_output"
    echo "-----------------------------------------------------------------"
    echo "请检查以上由AWS返回的错误信息以定位问题（例如权限不足或无税务信息可删）。"
fi

echo ""
echo "脚本执行完毕。"
