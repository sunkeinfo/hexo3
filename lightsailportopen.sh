#!/bin/bash

# ==============================================================================
#                 AWS Lightsail 防火墙全区域自动开放脚本
#
# 该脚本会遍历一个预定义的 AWS 区域列表，检查每个区域中的所有 Lightsail 实例。
# 如果实例的防火墙没有对所有 IP (IPv4 和 IPv6) 开放所有 TCP/UDP 端口，
# 脚本会自动更新防火墙规则以实现完全开放。
#
# 安全警告：
# 将所有端口对所有 IP 地址开放会使您的实例面临极高的安全风险。
# 此脚本仅应用于特殊测试或特定场景，切勿在生产环境中使用。
# ==============================================================================

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

    # 获取当前实例的端口状态，并明确指定区域
    port_states=$(aws lightsail get-instance-port-states --region "$region" --instance-name "$instance_name")

    # 检查 IPv4 规则
    ipv4_all_tcp_open=$(echo "$port_states" | jq '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "tcp" and (.cidrs | index("0.0.0.0/0")))')
    ipv4_all_udp_open=$(echo "$port_states" | jq '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "udp" and (.cidrs | index("0.0.0.0/0")))')

    # 检查 IPv6 规则
    ipv6_all_tcp_open=$(echo "$port_states" | jq '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "tcp" and (.ipv6Cidrs | index("::/0")))')
    ipv6_all_udp_open=$(echo "$port_states" | jq '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "udp" and (.ipv6Cidrs | index("::/0")))')

    # 如果 IPv4 或 IPv6 的 TCP 和 UDP 端口没有完全开放，则进行更新
    if [ -z "$ipv4_all_tcp_open" ] || [ -z "$ipv4_all_udp_open" ] || [ -z "$ipv6_all_tcp_open" ] || [ -z "$ipv6_all_udp_open" ]; then
      echo "    -> 发现防火墙端口未完全开放。正在为您打开所有端口..."

      aws lightsail put-instance-public-ports --region "$region" --instance-name "$instance_name" --port-infos \
        '[{"fromPort": 0, "toPort": 65535, "protocol": "tcp", "cidrs": ["0.0.0.0/0"], "ipv6Cidrs": ["::/0"]},
          {"fromPort": 0, "toPort": 65535, "protocol": "udp", "cidrs": ["0.0.0.0/0"], "ipv6Cidrs": ["::/0"]}]'

      echo "    -> 已成功为实例 $instance_name 打开所有 IPv4 和 IPv6 的 TCP/UDP 端口。"
      report_updated="$report_updated- $instance_name ($region)\n"
    else
      echo "    -> 防火墙端口已是完全开放状态，无需更改。"
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
  echo "以下实例的防火墙规则已更新为对所有 IPv4 和 IPv6 地址开放所有 TCP 和 UDP 端口："
  echo -e "$report_updated"
else
  echo "没有实例的防火墙规则需要更新。"
fi

echo "--------------------------------------------------"

if [ -n "$report_no_change" ]; then
  echo "以下实例的防火墙规则在检查时已是完全开放状态，未作任何更改："
  echo -e "$report_no_change"
else
  echo "没有实例的防火墙规则是完全开放状态。"
fi
echo "=================================================="
echo "所有区域检查完成。"```
