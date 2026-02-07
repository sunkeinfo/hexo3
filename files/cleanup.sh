#!/bin/bash

#====================================================
# 清理恶意脚本和程序
# 作用：删除恶意文件、停止恶意进程、清理配置
# 安全性：仅删除已知的恶意文件和进程
#====================================================

set -e

# 颜色定义
Red="\033[31m"
Green="\033[32m"
Yellow="\033[33m"
Font="\033[0m"

# 日志函数
log_info() {
    echo -e "${Green}[信息]${Font} $1"
}

log_warn() {
    echo -e "${Yellow}[警告]${Font} $1"
}

log_error() {
    echo -e "${Red}[错误]${Font} $1"
}

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    log_error "此脚本需要 root 权限运行"
    exit 1
fi

log_info "开始清理恶意文件和程序..."

# 1. 停止占用 8888 端口的进程
log_info "检查并停止占用 8888 端口的进程..."
if command -v lsof &> /dev/null; then
    PIDS=$(lsof -i :8888 -t 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        log_warn "发现占用 8888 端口的进程: $PIDS"
        for PID in $PIDS; do
            log_info "停止进程 $PID..."
            kill -9 "$PID" 2>/dev/null || true
        done
        log_info "进程已停止"
    else
        log_info "8888 端口未被占用"
    fi
else
    log_warn "lsof 命令不可用，跳过端口检查"
fi

# 2. 停止 sockd 服务
log_info "停止 sockd 服务..."
if systemctl is-active --quiet sockd.service 2>/dev/null; then
    systemctl stop sockd.service 2>/dev/null || true
    log_info "sockd 服务已停止"
fi

# 3. 禁用 sockd 服务
log_info "禁用 sockd 服务..."
if systemctl is-enabled sockd.service 2>/dev/null; then
    systemctl disable sockd.service 2>/dev/null || true
    log_info "sockd 服务已禁用"
fi

# 4. 删除恶意可执行文件
log_info "删除恶意可执行文件..."
MALICIOUS_FILES=(
    "/usr/local/bin/socks"
    "/usr/local/bin/sockd"
    "/root/ss5.txt"
    "/etc/socks/config.yaml"
    "/etc/systemd/system/sockd.service"
)

for file in "${MALICIOUS_FILES[@]}"; do
    if [ -f "$file" ] || [ -d "$file" ]; then
        log_info "删除: $file"
        rm -rf "$file"
    fi
done

# 5. 删除恶意目录
log_info "删除恶意目录..."
if [ -d "/etc/socks" ]; then
    log_info "删除目录: /etc/socks"
    rm -rf /etc/socks
fi

# 6. 重新加载 systemd
log_info "重新加载 systemd..."
systemctl daemon-reload

# 7. 检查并删除恶意脚本
log_info "检查并删除恶意脚本..."
SCRIPT_FILES=(
    "/root/ss5.sh"
    "/root/tcp.sh"
    "/tmp/tcp.sh"
    "/tmp/socks"
    "./ss5.sh"
    "./tcp.sh"
)

for script in "${SCRIPT_FILES[@]}"; do
    if [ -f "$script" ]; then
        log_warn "发现恶意脚本: $script"
        rm -f "$script"
        log_info "已删除: $script"
    fi
done

# 8. 检查并清理恶意的 cron 任务
log_info "检查 cron 任务..."
if crontab -l 2>/dev/null | grep -q "socks\|ss5\|tcp.sh"; then
    log_warn "发现可疑的 cron 任务，正在清理..."
    crontab -r 2>/dev/null || true
    log_info "cron 任务已清理"
fi

# 9. 检查并清理恶意的 systemd 定时器
log_info "检查 systemd 定时器..."
if [ -d "/etc/systemd/system" ]; then
    find /etc/systemd/system -name "*socks*" -o -name "*ss5*" | while read -r timer; do
        if [ -f "$timer" ]; then
            log_warn "发现恶意定时器: $timer"
            rm -f "$timer"
        fi
    done
fi

# 10. 检查网络配置是否被篡改
log_info "检查网络配置..."
if grep -q "ip_forward\|route_localnet" /etc/sysctl.conf 2>/dev/null; then
    log_warn "检测到网络配置被修改"
    log_info "建议手动检查 /etc/sysctl.conf 和 /etc/sysctl.d/ 目录"
fi

# 11. 检查是否有可疑的后台进程
log_info "检查可疑的后台进程..."
SUSPICIOUS_PROCS=("socks" "sockd" "ss5" "oofeye")
for proc in "${SUSPICIOUS_PROCS[@]}"; do
    if pgrep -f "$proc" > /dev/null 2>&1; then
        log_warn "发现可疑进程: $proc"
        pkill -9 -f "$proc" 2>/dev/null || true
        log_info "已终止进程: $proc"
    fi
done

# 12. 清理临时文件
log_info "清理临时文件..."
rm -f /tmp/tcp.sh /tmp/socks /tmp/ss5.sh 2>/dev/null || true

log_info "清理完成！"
log_info ""
log_info "建议的后续操作："
log_info "1. 检查系统日志: journalctl -xe"
log_info "2. 检查网络连接: netstat -tulpn 或 ss -tulpn"
log_info "3. 检查已安装的包: apt list --installed | grep -i socks"
log_info "4. 考虑更改所有重要密码"
log_info "5. 检查 SSH 密钥是否被篡改"
log_info ""
log_info "清理脚本执行完毕"
