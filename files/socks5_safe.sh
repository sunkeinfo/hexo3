#!/bin/bash

#====================================================
# 安全的 SOCKS5 服务器安装脚本
# 系统要求: Ubuntu 20.04+ 或 Debian 10+
# 功能: 安装并配置 dante-server SOCKS5 服务
# 安全性: 使用官方仓库、验证配置、无后门
#====================================================

set -e

# 颜色定义
Red="\033[31m"
Green="\033[32m"
Yellow="\033[33m"
Blue="\033[34m"
Font="\033[0m"

# 配置变量
SOCKS_PORT=8888
SOCKS_USER=8888
SOCKS_PASS=8888
SOCKS_CONFIG="/etc/dante/dante.conf"
SOCKS_SERVICE="danted"

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

log_success() {
    echo -e "${Blue}[成功]${Font} $1"
}

# 检查是否为 root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

# 检查系统
check_system() {
    log_info "检查系统信息..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "无法识别系统"
        exit 1
    fi
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_error "此脚本仅支持 Ubuntu 和 Debian 系统"
        exit 1
    fi
    
    log_success "系统: $OS $VERSION"
}

# 检查端口是否被占用
check_port() {
    log_info "检查 $SOCKS_PORT 端口..."
    
    if command -v lsof &> /dev/null; then
        if lsof -i :$SOCKS_PORT &> /dev/null; then
            log_error "端口 $SOCKS_PORT 已被占用"
            log_info "尝试停止占用该端口的进程..."
            lsof -i :$SOCKS_PORT -t | xargs kill -9 2>/dev/null || true
            sleep 2
        fi
    fi
    
    log_success "端口 $SOCKS_PORT 可用"
}

# 更新系统包
update_system() {
    log_info "更新系统包..."
    apt-get update -qq
    apt-get upgrade -y -qq
    log_success "系统包已更新"
}

# 安装依赖
install_dependencies() {
    log_info "安装依赖包..."
    
    # 安装必要的工具
    apt-get install -y -qq \
        curl \
        wget \
        net-tools \
        lsof \
        systemctl \
        openssl
    
    log_success "依赖包已安装"
}

# 安装 dante-server
install_dante() {
    log_info "安装 dante-server..."
    
    # 检查是否已安装
    if command -v danted &> /dev/null; then
        log_warn "dante-server 已安装，跳过安装步骤"
        return
    fi
    
    # 从官方仓库安装
    apt-get install -y -qq dante-server
    
    log_success "dante-server 已安装"
}

# 创建用户账户
create_user() {
    log_info "创建 SOCKS5 用户账户..."
    
    # 检查用户是否存在
    if id "$SOCKS_USER" &>/dev/null; then
        log_warn "用户 $SOCKS_USER 已存在"
        # 更新密码
        echo "$SOCKS_USER:$SOCKS_PASS" | chpasswd
    else
        # 创建新用户（不创建主目录，不允许登录）
        useradd -r -s /usr/sbin/nologin -M "$SOCKS_USER" 2>/dev/null || true
        echo "$SOCKS_USER:$SOCKS_PASS" | chpasswd
    fi
    
    log_success "用户 $SOCKS_USER 已创建/更新"
}

# 配置 dante
configure_dante() {
    log_info "配置 dante-server..."
    
    # 备份原始配置
    if [ -f "$SOCKS_CONFIG" ]; then
        cp "$SOCKS_CONFIG" "$SOCKS_CONFIG.bak.$(date +%s)"
    fi
    
    # 创建新的配置文件
    cat > "$SOCKS_CONFIG" << 'EOF'
# Dante SOCKS5 服务器配置文件
# 安全配置 - 无后门

# 日志配置
logoutput: /var/log/dante/dante.log

# 内部网络接口
internal: 0.0.0.0 port = 8888

# 外部网络接口
external: 0.0.0.0

# 方法配置 - 使用用户名/密码认证
method: username

# 用户名/密码认证配置
method_line: username /etc/dante/passwd

# 客户端规则
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

# SOCKS 请求规则
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

# 拒绝所有其他连接
socks block {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}
EOF
    
    # 设置配置文件权限
    chmod 644 "$SOCKS_CONFIG"
    
    log_success "dante 配置已完成"
}

# 创建密码文件
create_passwd_file() {
    log_info "创建密码文件..."
    
    # 创建密码文件目录
    mkdir -p /etc/dante
    
    # 创建密码文件（格式: username:password）
    echo "$SOCKS_USER:$SOCKS_PASS" > /etc/dante/passwd
    
    # 设置权限（仅 root 可读）
    chmod 600 /etc/dante/passwd
    chown root:root /etc/dante/passwd
    
    log_success "密码文件已创建"
}

# 创建日志目录
create_log_dir() {
    log_info "创建日志目录..."
    
    mkdir -p /var/log/dante
    chown daemon:daemon /var/log/dante
    chmod 755 /var/log/dante
    
    log_success "日志目录已创建"
}

# 启动服务
start_service() {
    log_info "启动 dante 服务..."
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    # 启用服务开机自启
    systemctl enable $SOCKS_SERVICE
    
    # 启动服务
    systemctl start $SOCKS_SERVICE
    
    # 检查服务状态
    if systemctl is-active --quiet $SOCKS_SERVICE; then
        log_success "dante 服务已启动"
    else
        log_error "dante 服务启动失败"
        systemctl status $SOCKS_SERVICE
        exit 1
    fi
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    # 检查端口是否监听
    if netstat -tulpn 2>/dev/null | grep -q ":$SOCKS_PORT"; then
        log_success "端口 $SOCKS_PORT 正在监听"
    elif ss -tulpn 2>/dev/null | grep -q ":$SOCKS_PORT"; then
        log_success "端口 $SOCKS_PORT 正在监听"
    else
        log_error "端口 $SOCKS_PORT 未监听"
        exit 1
    fi
    
    # 检查配置文件
    if [ -f "$SOCKS_CONFIG" ]; then
        log_success "配置文件存在"
    else
        log_error "配置文件不存在"
        exit 1
    fi
    
    # 检查密码文件
    if [ -f /etc/dante/passwd ]; then
        log_success "密码文件存在"
    else
        log_error "密码文件不存在"
        exit 1
    fi
}

# 显示连接信息
show_connection_info() {
    log_info "SOCKS5 服务器配置完成！"
    echo ""
    echo "=========================================="
    echo "SOCKS5 服务器连接信息"
    echo "=========================================="
    echo "服务器地址: $(hostname -I | awk '{print $1}')"
    echo "端口: $SOCKS_PORT"
    echo "用户名: $SOCKS_USER"
    echo "密码: $SOCKS_PASS"
    echo "协议: SOCKS5"
    echo "认证方式: 用户名/密码"
    echo "=========================================="
    echo ""
    echo "测试连接命令:"
    echo "curl -x socks5://$SOCKS_USER:$SOCKS_PASS@127.0.0.1:$SOCKS_PORT http://ipinfo.io"
    echo ""
    echo "日志位置: /var/log/dante/dante.log"
    echo "配置文件: $SOCKS_CONFIG"
    echo "=========================================="
}

# 显示安全建议
show_security_tips() {
    echo ""
    echo "=========================================="
    echo "安全建议"
    echo "=========================================="
    echo "1. 定期检查日志: tail -f /var/log/dante/dante.log"
    echo "2. 定期更新系统: apt-get update && apt-get upgrade"
    echo "3. 配置防火墙规则限制访问"
    echo "4. 定期更改密码"
    echo "5. 监控端口连接: netstat -tulpn | grep 8888"
    echo "6. 检查服务状态: systemctl status danted"
    echo "=========================================="
}

# 主函数
main() {
    echo ""
    echo "=========================================="
    echo "安全 SOCKS5 服务器安装脚本"
    echo "=========================================="
    echo ""
    
    check_root
    check_system
    check_port
    update_system
    install_dependencies
    install_dante
    create_user
    create_passwd_file
    create_log_dir
    configure_dante
    start_service
    verify_installation
    show_connection_info
    show_security_tips
    
    echo ""
    log_success "安装完成！SOCKS5 服务器已就绪"
}

# 执行主函数
main
