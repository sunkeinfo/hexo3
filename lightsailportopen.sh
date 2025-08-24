#!/bin/bash

# 获取所有 Lightsail 实例的名称
instance_names=$(aws lightsail get-instances --query "instances[*].name" --output text)

# 检查是否获取到实例
if [ -z "$instance_names" ]; then
  echo "在您的账户中没有找到任何 Lightsail 实例。"
  exit 0
fi

echo "开始检查所有 Lightsail 实例的防火墙规则..."
echo "--------------------------------------------------"

# 初始化报告变量
report_updated=""
report_no_change=""

# 遍历所有实例
for instance_name in $instance_names; do
  echo "正在检查实例: $instance_name"

  # 获取当前实例的端口状态
  port_states=$(aws lightsail get-instance-port-states --instance-name "$instance_name")

  # 检查 IPv4 规则
  ipv4_all_tcp_open=$(echo "$port_states" | jq '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "tcp" and (.cidrs | index("0.0.0.0/0")))')
  ipv4_all_udp_open=$(echo "$port_states" | jq '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "udp" and (.cidrs | index("0.0.0.0/0")))')

  # 检查 IPv6 规则
  ipv6_all_tcp_open=$(echo "$port_states" | jq '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "tcp" and (.ipv6Cidrs | index("::/0")))')
  ipv6_all_udp_open=$(echo "$port_states" | jq '.portStates[] | select(.fromPort == 0 and .toPort == 65535 and .protocol == "udp" and (.ipv6Cidrs | index("::/0")))')

  # 如果 IPv4 或 IPv6 的 TCP 和 UDP 端口没有完全开放，则进行更新
  if [ -z "$ipv4_all_tcp_open" ] || [ -z "$ipv4_all_udp_open" ] || [ -z "$ipv6_all_tcp_open" ] || [ -z "$ipv6_all_udp_open" ]; then
    echo "  -> 发现防火墙端口未完全开放。正在为您打开所有端口..."
    
    aws lightsail put-instance-public-ports --instance-name "$instance_name" --port-infos \
      '[{"fromPort": 0, "toPort": 65535, "protocol": "tcp", "cidrs": ["0.0.0.0/0"], "ipv6Cidrs": ["::/0"]},
        {"fromPort": 0, "toPort": 65535, "protocol": "udp", "cidrs": ["0.0.0.0/0"], "ipv6Cidrs": ["::/0"]}]'
    
    echo "  -> 已成功为实例 $instance_name 打开所有 IPv4 和 IPv6 的 TCP/UDP 端口。"
    report_updated="$report_updated- $instance_name\n"
  else
    echo "  -> 防火墙端口已是完全开放状态，无需更改。"
    report_no_change="$report_no_change- $instance_name\n"
  fi
  echo "--------------------------------------------------"
done

# 生成最终报告
echo "=================================================="
echo "                 工作汇报结果"
echo "=================================================="
if [ -n "$report_updated" ]; then
  echo "以下实例的防火墙规则已更新为对所有 IPv4 和 IPv6 地址开放所有 TCP 和 UDP 端口："
  echo -e "$report_updated"
else
  echo "没有实例的防火墙规则需要更新。"
fi

if [ -n "$report_no_change" ]; then
  echo "以下实例的防火墙规则在检查时已是完全开放状态，未作任何更改："
  echo -e "$report_no_change"
else
  echo "没有实例的防火墙规则是完全开放状态。"
fi
echo "=================================================="
echo "检查完成。"
