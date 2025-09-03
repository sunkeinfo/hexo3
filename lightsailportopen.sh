#!/bin/bash

# ==============================================================================
#           AWS Lightsail 防火墙全区域自动配置脚本 (增强版)
#
# 该脚本会遍历一个预定义的 AWS 区域列表，检查每个区域中的所有 Lightsail 实例。
#
# 功能：
# 脚本会检查实例的防火墙规则是否与下面配置的 TARGET_IPV4_CIDR 和
# TARGET_IPV6_CIDR 相匹配 (针对所有 TCP/UDP 端口)。如果不匹配，
# 它会自动替换现有规则，以确保所有端口只对指定的 IP 地址或范围开放。
#
# 安全警告：
# - 此脚本会 **替换** 实例上现有的所有防火墙规则。
# - 将所有端口对 "0.0.0.0/0" (所有 IPv4) 和 "::/0" (所有 IPv6) 开放会使
#   您的实例面临极高的安全风险。请仅在明确了解风险的情况下使用默认配置。
# - 建议将其配置为您的特定 IP 地址以增强安全性。
# ==============================================================================

# ==============================================================================
#                 ★★★★★ 在这里配置目标 IP 地址 ★★★★★
#
# 在此处设置您希望开放所有端口的特定 IPv4 和 IPv6 地址或范围 (CIDR 格式)。
# 默认值为 "0.0.0.0/0" 和 "::/0"，即对所有 IP 开放 (原始脚本功能)。
#
# 示例:
# - 仅对您自己的 IPv4 地址开放: TARGET_IPV4_CIDR="1.2.3.4/32"
# - 仅对您自己的 IPv6 地址开放: TARGET_IPV6_CIDR="2001:db8:1234::1/128"
# - 对一个公司的子网开放:     TARGET_IPV4_CIDR="203.0.113.0/24"
# ==============================================================================
TARGET_IPV4_CIDR="0.0.0.0/0"
TARGET_IPV6_CIDR="::/0"


# 定义要扫描的所有 Lightsail 区域
regions=(
  "us-east-1"      # N. Virginia
  "us-east-2"      # Ohio
  "us-west-2"      # Oregon
  "ap-south-1"     # Mumbai
  "ap-northeast-1" # Tokyo
  "ap-northeast-2" # Seoul
  "ap-southeast-1" # Singapore
  "ap-southeast-2" # Sydney
  "ap-southeast-3" # Jakarta
  "ca-central-1"   # Canada (Central)
  "eu-central-1"   # Frankfurt
  "eu-west-1"      # Ireland
  "eu-west-2"      # London
  "eu-west-3"      # Paris
  "eu-north-1"     # Stockholm
)

# 初始化报告变量
report_updated=""
report_no_change=""
found_any_instance=false

echo "开始扫描所有指定区域的 Lightsail 实例防火墙规则..."
echo "目标规则: 所有 TCP/UDP 端口对 IPv4 [$TARGET_IPV4_CIDR] 和 IPv6 [$TARGET_IPV6_CIDR] 开放。"
echo "=================================================="

# 遍历所有定义的区域
for region in "${regions[@]}"; do
  echo "正在扫描区域: $region"

  # 获取当前区域所有 Lightsail 实例的名称
  # 2>/dev/null 会抑制因区域未启用等原因产生的错误信息，使输出更干净
  instance_names=$(aws lightsail get-instances --region "$region" --query "instances[*].name" --output text 2>/dev/null)

  # 检查当前区域是否获取到实例
  if [ -z "$instance_names" ]; then
    echo "  -> 在区域 $region 中没有找到任何 Lightsail 实例。"
    echo "--------------------------------------------------"
    continue
  fi

  # 标记至少找到了一个实例
  found_any_instance=true

  # 遍历当前区域的所有实例
  for instance_name in $instance_names; do
    echo "  正在检查实例: $instance_name (区域: $region)"

    # 获取当前实例的端口状态
    port_states=$(aws lightsail get-instance-port-states --region "$region" --instance-name "$instance_name")

    # 检查 TCP 规则是否与目标配置匹配
    tcp_rule_exists=$(echo "$port_states" | jq --arg ipv4cidr "$TARGET_IPV4_CIDR" --arg ipv6cidr "$TARGET_IPV6_CIDR" \
      '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "tcp" and (.cidrs | index($ipv4cidr)) and (.ipv6Cidrs | index($ipv6cidr)))')

    # 检查 UDP 规则是否与目标配置匹配
    udp_rule_exists=$(echo "$port_states" | jq --arg ipv4cidr "$TARGET_IPV4_CIDR" --arg ipv6cidr "$TARGET_IPV6_CIDR" \
      '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "udp" and (.cidrs | index($ipv4cidr)) and (.ipv6Cidrs | index($ipv6cidr)))')

    # 如果任一规则不存在或不匹配，则进行更新
    if [ -z "$tcp_rule_exists" ] || [ -z "$udp_rule_exists" ]; then
      echo "    -> 防火墙规则与目标配置不匹配。正在更新..."

      # 使用变量构建 JSON payload
      port_info_json=$(cat <<EOF
[
  {
    "fromPort": 0,
    "toPort": 65535,
    "protocol": "tcp",
    "cidrs": ["$TARGET_IPV4_CIDR"],
    "ipv6Cidrs": ["$TARGET_IPV6_CIDR"]
  },
  {
    "fromPort": 0,
    "toPort": 65535,
    "protocol": "udp",
    "cidrs": ["$TARGET_IPV4_CIDR"],
    "ipv6Cidrs": ["$TARGET_IPV6_CIDR"]
  }
]
EOF
)
      # 执行更新命令
      aws lightsail put-instance-public-ports --region "$region" --instance-name "$instance_name" --port-infos "$port_info_json"

      echo "    -> 已成功为实例 $instance_name 设置防火墙，将所有 TCP/UDP 端口开放给 IPv4: $TARGET_IPV4_CIDR 和 IPv6: $TARGET_IPV6_CIDR。"
      report_updated="$report_updated- $instance_name ($region)\n"
    else
      echo "    -> 防火墙规则已符合目标配置，无需更改。"
      report_no_change="$report_no_change- $instance_name ($region)\n"
    fi
  done
  echo "--------------------------------------------------"
done

# 生成最终报告
echo "=================================================="
echo "                 工作汇报结果"
echo "=================================================="

if [ "$found_any_instance" = false ]; then
  echo "在所有扫描的 AWS 区域中均未找到任何 Lightsail 实例。"
  echo "=================================================="
  echo "检查完成。"
  exit 0
fi

if [ -n "$report_updated" ]; then
  echo "以下实例的防火墙规则已更新为对 IPv4 [$TARGET_IPV4_CIDR] 和 IPv6 [$TARGET_IPV6_CIDR] 开放所有 TCP/UDP 端口："
  echo -e "$report_updated"
else
  echo "没有实例的防火墙规则需要更新。"
fi

echo "--------------------------------------------------"

if [ -n "$report_no_change" ]; then
  echo "以下实例的防火墙规则在检查时已符合目标配置，未作任何更改："
  echo -e "$report_no_change"
else
  echo "没有实例的防火墙规则是符合目标配置的状态。"
fi
echo "=================================================="
echo "所有区域检查完成。"
