#!/bin/bash

# --- 脚本设置 ---
# set -e: 任何命令执行失败则立即退出脚本，保证安全性。
set -e
# set -o pipefail: 管道命令中任一环节失败，整个管道都算失败。
set -o pipefail

# --- 脚本主体 ---

echo "--- 脚本开始：准备更新 AWS 税务信息为澳大利亚信息 ---"

# --- 步骤 1: 删除已有的税务信息 ---
# 尝试删除旧配置，|| true 确保在没有旧配置时脚本不会因报错而退出。
echo "正在尝试删除旧的税务信息（如果存在）..."
aws taxsettings delete-tax-registration --region us-east-1 || true
echo "旧税务信息删除操作完成。"

# --- 步骤 2: 准备新的澳大利亚税务信息 (JSON 格式) ---
# **[最终验证修正]** 根据所有 AWS API 错误提示进行修正：
# 1. "taxRegistrationType"  ->  "registrationType"
# 2. "address" 对象          ->  "legalAddress"
# 3. "registrationType" 的值 -> "GST"
# 4. "sector" 的值         -> "Business" (根据最新的错误日志精确修正)
echo "正在准备新的税务信息 JSON 数据..."
TAX_INFO='{
  "taxRegistrationEntry": {
    "registrationType": "GST",
    "legalName": "ooo",
    "registrationId": "84402315608",
    "sector": "Business",
    "legalAddress": {
      "addressLine1": "ooo",
      "addressLine2": "o",
      "city": "oo",
      "stateOrRegion": "o",
      "postalCode": "2233",
      "countryCode": "AU"
    }
  }
}'

# --- 步骤 3: 更新税务信息 ---
# 使用 put-tax-registration 命令提交新的税务信息。
echo "正在提交新的税务信息至 AWS..."
aws taxsettings put-tax-registration --cli-input-json "$TAX_INFO" --region us-east-1

# --- 步骤 4: 输出成功信息 ---
echo "--- 成功 ---"
echo "AWS 税务信息已成功更新为指定的澳大利亚信息！"
echo "国家/地区: Australia"
echo "税务登记号 (TRN/ABN): 84402315608"
