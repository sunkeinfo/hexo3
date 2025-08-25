#!/bin/bash

# --- 脚本设置 ---
# set -e: 脚本中的任何命令如果执行失败（返回非零退出码），则立即退出脚本。
# 这可以防止脚本在出错后继续执行，从而导致意想不到的后果。
set -e

# set -o pipefail: 在管道命令中，只要有任何一个命令失败，整个管道命令的返回值都为失败。
# 例如 a | b | c，如果 b 命令失败了，整个管道命令就会被认为是失败的。
set -o pipefail

# --- 脚本主体 ---

echo "--- 脚本开始：准备更新 AWS 税务信息 ---"

# --- 步骤 1: 生成随机的税务登记号 ---
# 生成一个随机的9位数，用于 PAN/VAT 注册号。
# shuf 命令可以用来生成随机排列。
# -i 100000000-999999999 表示从 100000000 到 999999999 的整数范围。
# -n 1 表示只取其中的 1 个随机数。
VAT_NUMBER=$(shuf -i 100000000-999999999 -n 1)
echo "已生成新的随机 PAN/VAT 注册号: $VAT_NUMBER"

# --- 步骤 2: 删除已有的税务信息 ---
# 这是 AWS CLI 命令，用于删除账户中已有的税务登记信息。
# 在更新之前先删除，可以避免因已有配置冲突而导致的更新失败。
# --region us-east-1 指定操作的 AWS 区域。税务信息是全局服务，但 CLI 通常需要指定一个区域，us-east-1 是一个常用选项。
# '|| true' 表示如果删除命令失败（例如，因为原本就没有税务信息），则忽略错误，继续执行脚本。
echo "正在尝试删除旧的税务信息（如果存在）..."
aws taxsettings delete-tax-registration --region us-east-1 || true
echo "旧税务信息删除操作完成。"

# --- 步骤 3: 准备新的税务信息 (JSON 格式) ---
# 使用 'read' 和 'heredoc' (<< EOM ... EOM) 的方式，将一大段 JSON 文本赋值给变量 TAX_INFO。
# -r 选项可以防止反斜杠字符被解释。
# -d '' 选项确保可以完整读取多行内容。
# JSON 中的 "$VAT_NUMBER" 会被替换为上面生成的随机数字。
echo "正在准备新的税务信息 JSON 数据..."
read -r -d '' TAX_INFO << EOM
{
  "taxRegistrationEntry": {
    "taxRegistrationType": "Individual Customer (Default)",
    "legalName": "uuu",
    "registrationId": "$VAT_NUMBER",
    "sector": "Individual",
    "address": {
      "addressLine1": "u",
      "addressLine2": "uu",
      "city": "uu",
      "stateOrRegion": "u",
      "postalCode": "uu",
      "countryCode": "NP"
    }
  }
}
EOM

# --- 步骤 4: 更新税务信息 ---
# 这是 AWS CLI 命令，用于上传并设置新的税务登记信息。
# --cli-input-json "$TAX_INFO" 参数告诉 AWS CLI 直接从我们准备好的 TAX_INFO 变量中读取 JSON 数据作为输入。
echo "正在提交新的税务信息至 AWS..."
aws taxsettings put-tax-registration --cli-input-json "$TAX_INFO" --region us-east-1

# --- 步骤 5: 输出成功信息 ---
# 脚本成功执行到这里后，输出成功信息。
echo "--- 成功 ---"
echo "AWS 税务信息已成功更新！"
echo "新生成的 PAN/VAT 注册号是: $VAT_NUMBER"
