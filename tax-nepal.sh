#!/bin/bash

# --- 脚本设置 ---
set -e
set -o pipefail

# --- 脚本主体 ---

echo "--- 脚本开始：准备更新 AWS 税务信息 (尼泊尔) ---"

# --- 步骤 1: 生成随机的税务登记号 ---
# 为尼泊尔的税务信息生成一个随机的9位数字。
VAT_NUMBER=$(shuf -i 100000000-999999999 -n 1)
echo "已生成新的随机税务注册号: $VAT_NUMBER"

# --- 步骤 2: 删除已有的税务信息 ---
echo "正在尝试删除旧的税务信息（如果存在）..."
aws taxsettings delete-tax-registration --region us-east-1 || true
echo "旧税务信息删除操作完成。"

# --- 步骤 3: 准备新的税务信息 (JSON 格式) ---
# **[核心修正]** 根据 AWS API 的报错，"PAN" 类型会触发印度专属的验证规则。
# 我们将其更改为对尼泊尔同样适用的 "VAT" 类型，以避免该冲突。
echo "正在准备新的税务信息 JSON 数据..."
TAX_INFO='{
  "taxRegistrationEntry": {
    "registrationType": "VAT",
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
echo "正在提交新的税务信息至 AWS..."
aws taxsettings put-tax-registration --cli-input-json "$TAX_INFO" --region us-east-1

# --- 步骤 5: 输出成功信息 ---
echo "--- 成功 ---"
echo "AWS 税务信息已成功更新！"
echo "国家/地区: Nepal"
echo "新生成的税务注册号是: $VAT_NUMBER"
