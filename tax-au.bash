#!/bin/bash

# --- 脚本设置 ---
# set -e: 脚本中的任何命令如果执行失败（返回非零退出码），则立即退出脚本。
# 这是一个很好的安全实践，可以防止在出错后继续执行不完整的操作。
set -e

# set -o pipefail: 在管道命令中，只要有任何一个命令失败，整个管道命令的返回值都为失败。
set -o pipefail

# --- 脚本主体 ---

echo "--- 脚本开始：准备更新 AWS 税务信息为澳大利亚信息 ---"

# --- 步骤 1: 删除已有的税务信息 ---
# 在更新之前先执行删除操作，可以确保一个干净的配置状态，避免潜在的冲突。
# '|| true' 确保了即使当前没有税务信息（导致删除失败），脚本也不会因此退出。
echo "正在尝试删除旧的税务信息（如果存在）..."
aws taxsettings delete-tax-registration --region us-east-1 || true
echo "旧税务信息删除操作完成。"

# --- 步骤 2: 准备新的澳大利亚税务信息 (JSON 格式) ---
# 使用 'heredoc' 语法将多行的 JSON 文本赋值给变量 TAX_INFO。
# JSON 数据结构是根据 AWS tax-settings API 的要求构建的。
# - 对于澳大利亚，Tax registration type 通常是 ABN (Australian Business Number)。
# - 其他信息均根据您提供的细节填写。
echo "正在准备新的税务信息 JSON 数据..."
read -r -d '' TAX_INFO << EOM
{
  "taxRegistrationEntry": {
    "taxRegistrationType": "ABN",
    "legalName": "ooo",
    "registrationId": "84402315608",
    "sector": "Business",
    "address": {
      "addressLine1": "ooo",
      "addressLine2": "o",
      "city": "oo",
      "stateOrRegion": "o",
      "postalCode": "2233",
      "countryCode": "AU"
    }
  }
}
EOM

# --- 步骤 3: 更新税务信息 ---
# 使用 'put-tax-registration' 命令将新的税务信息提交到 AWS。
# --cli-input-json "$TAX_INFO" 参数让 AWS CLI 直接从我们准备好的 TAX_INFO 变量中读取 JSON 数据。
echo "正在提交新的税务信息至 AWS..."
aws taxsettings put-tax-registration --cli-input-json "$TAX_INFO" --region us-east-1

# --- 步骤 4: 输出成功信息 ---
# 脚本成功执行到这里后，输出最终的成功信息。
echo "--- 成功 ---"
echo "AWS 税务信息已成功更新为指定的澳大利亚信息！"
echo "国家/地区: Australia"
echo "税务登记号 (TRN/ABN): 84402315608"
