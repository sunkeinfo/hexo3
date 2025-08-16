#!/bin/bash

# 这个脚本用于创建一个新的 AWS Organizations 账户。
# 它会自动将账户名设置为电子邮件地址中 @ 符号之前的部分。
#
# 用法:
#   curl -sL https://raw.githubusercontent.com/your-username/your-repo/main/create-org-account-simple.sh | bash -s --dev-team@example.com
#
# 确保你已正确配置了 AWS CLI 的权限，并且系统中已安装 'jq' 工具。

# 检查参数是否正确，并提取电子邮件
if [ -z "$1" ] || [[ ! "$1" =~ ^-- ]]; then
  echo "错误: 未提供正确的电子邮件地址格式。"
  echo "用法: $0 --your-email@example.com"
  exit 1
fi

# 从第一个参数中移除前缀 "--"
EMAIL="${1:2}"

# 从电子邮件地址中提取账户名
ACCOUNT_NAME=$(echo "$EMAIL" | cut -d'@' -f1)

# 一个简单的检查，确保账户名不为空
if [ -z "$ACCOUNT_NAME" ]; then
  echo "错误: 无法从电子邮件地址中获取账户名。"
  exit 1
fi

echo "正在尝试创建新的 AWS Organizations 账户..."
echo "账户名: ${ACCOUNT_NAME}"
echo "电子邮件: ${EMAIL}"

# 执行 AWS CLI 命令，并将输出保存在一个变量中
RESULT=$(aws organizations create-account \
    --email "${EMAIL}" \
    --account-name "${ACCOUNT_NAME}" \
    --query 'CreateAccountStatus' --output json 2>&1)

# 检查命令是否执行成功
if [ $? -eq 0 ]; then
  echo "账户创建请求已成功提交。"
  
  if ! command -v jq &> /dev/null
  then
      echo "警告: 'jq' 命令未找到，无法解析详细结果。"
      echo "原始返回信息如下:"
      echo "${RESULT}"
      exit 0
  fi

  # 解析 JSON 结果并显示关键信息
  ACCOUNT_ID=$(echo "${RESULT}" | jq -r '.AccountId')
  ACCOUNT_STATUS=$(echo "${RESULT}" | jq -r '.State')

  echo "----------------------------------------"
  echo "账户ID: ${ACCOUNT_ID}"
  echo "账户状态: ${ACCOUNT_STATUS}"
  echo "----------------------------------------"
  echo "一封邮件已发送至 ${EMAIL}。请检查你的收件箱以完成账户设置。"
else
  echo "创建 AWS Organizations 账户失败。"
  echo "错误信息:"
  echo "${RESULT}"
  exit 1
fi
