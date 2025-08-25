#!/bin/bash

# --- 脚本设置 ---
# set -e: 脚本中的任何命令如果执行失败（返回非零退出码），则立即退出脚本。
set -e
# set -o pipefail: 在管道命令中，只要有任何一个命令失败，整个管道命令的返回值都为失败。
set -o pipefail

# --- 脚本主体 ---

echo "--- 脚本开始：准备更新 AWS 税务信息 (尼泊尔) ---"

# --- 步骤 1: 生成随机的税务登记号 ---
# 为尼泊尔的 PAN 生成一个随机的9位数字。
VAT_NUMBER=$(shuf -i 100000000-999999999 -n 1)
echo "已生成新的随机 PAN 注册号: $VAT_NUMBER"

# --- 步骤 2: 删除已有的税务信息 ---
# 在更新前删除，确保一个干净的初始状态。
# '|| true' 确保在账户中本就没有税务信息时，脚本不会因“资源未找到”的错误而退出。
echo "正在尝试删除旧的税务信息（如果存在）..."
aws taxsettings delete-tax-registration --region us-east-1 || true
echo "旧税务信息删除操作完成。"

# --- 步骤 3: 准备新的税务信息 (JSON 格式) ---
# **[核心修正]** 应用我们总结的经验对 JSON 结构进行修正：
# 1. "taxRegistrationType"  ->  "registrationType" (正确的 API 参数名)
# 2. "Individual Customer (Default)" -> "PAN" (正确的 API 枚举值)
# 3. "address" -> "legalAddress" (正确的 API 参数名)
# 4. 完全移除了可选的 "sector" 字段，以避免不必要的验证错误。
echo "正在准备新的税务信息 JSON 数据..."
TAX_INFO='{
  "taxRegistrationEntry": {
    "registrationType": "PAN",
    "legalName": "uuu",
    "registrationId": "'"$VAT_NUMBER"'",
    "legalAddress": {
      "addressLine1": "u",
      "addressLine2": "uu",
      "city": "uu",
      "stateOrRegion": "u",
      "postalCode": "uu",
      "countryCode": "NP"
    }
  }
}'

# --- 步骤 4: 更新税务信息 ---
# 使用 aws taxsettings put-tax-registration 命令提交 JSON 数据。
echo "正在提交新的税务信息至 AWS..."
aws taxsettings put-tax-registration --cli-input-json "$TAX_INFO" --region us-east-1

# --- 步骤 5: 输出成功信息 ---
echo "--- 成功 ---"
echo "AWS 税务信息已成功更新！"
echo "国家/地区: Nepal"
echo "新生成的 PAN 注册号是: $VAT_NUMBER"
