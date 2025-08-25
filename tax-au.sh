#!/bin/bash
set -e
set -o pipefail
echo "--- 脚本开始：测试 Business Sector ---"
echo "正在尝试删除旧的税务信息（如果存在）..."
aws taxsettings delete-tax-registration --region us-east-1 || true
echo "旧税务信息删除操作完成。"
echo "正在准备新的税务信息 JSON 数据..."
TAX_INFO='{
  "taxRegistrationEntry": {
    "registrationType": "GST",
    "legalName": "ooo",
    "registrationId": "84402315608",
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
echo "正在提交新的税务信息至 AWS..."
aws taxsettings put-tax-registration --cli-input-json "$TAX_INFO" --region us-east-1
echo "--- 成功 ---"
echo "AWS 税务信息已成功更新！"
echo "账户类型 (Sector): Business"
