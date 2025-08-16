#!/bin/bash

# 检查是否提供了用户名和密码
if [ "$#" -ne 2 ]; then
    echo "使用方法: $0 <用户名> <密码>"
    exit 1
fi

USERNAME=$1
PASSWORD=$2

# 1. 创建 IAM 用户
echo "正在创建 IAM 用户: $USERNAME..."
aws iam create-user --user-name $USERNAME

# 2. 为用户设置登录密码
echo "正在为用户设置登录密码..."
aws iam create-login-profile --user-name $USERNAME --password $PASSWORD --no-password-reset-required

# 3. 附加管理员权限策略
echo "正在为用户附加管理员权限..."
aws iam attach-user-policy --user-name $USERNAME --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# 4. 获取 AWS 账户ID并构建登录URL
echo "正在获取账户信息..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LOGIN_URL="https://${ACCOUNT_ID}.signin.aws.amazon.com/console"

# 5. 输出登录信息
echo "---"
echo "IAM 用户创建成功！"
echo "用户名: $USERNAME"
echo "密  码: $PASSWORD"
echo "登录地址: $LOGIN_URL"
echo "---"
