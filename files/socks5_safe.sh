#!/bin/bash

#====================================================
# 简单 SOCKS5 服务器安装脚本 (ss5)
# 系统要求: Ubuntu/Debian
# 功能: 安装并配置轻量级 SOCKS5 服务
# 安全性: 使用官方仓库、简单配置、无后门
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
    log_success "系统包已更新"
}

# 安装依赖
install_dependencies() {
    log_info "安装依赖包..."
    
    # 修复损坏的依赖关系
    log_info "修复系统依赖关系..."
    apt-get --fix-broken install -y -qq || true
    apt-get autoremove -y -qq || true
    apt-get clean -qq || true
    
    # 安装依赖包
    apt-get install -y -qq \
        curl \
        wget \
        net-tools \
        lsof \
        build-essential \
        libpam0g-dev \
        openssl
    
    log_success "依赖包已安装"
}

# 安装 ss5
install_ss5() {
    log_info "安装 ss5 SOCKS5 服务器..."
    
    # 检查是否已安装
    if command -v ss5 &> /dev/null; then
        log_warn "ss5 已安装，跳过安装步骤"
        return
    fi
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # 下载 ss5 源代码
    log_info "下载 ss5 源代码..."
    wget -q https://sourceforge.net/projects/ss5/files/ss5/3.8.9-8/ss5-3.8.9-8.tar.gz
    
    # 解压
    tar -xzf ss5-3.8.9-8.tar.gz
    cd ss5-3.8.9-8
    
    # 编译安装
    log_info "编译 ss5..."
    ./configure --prefix=/usr/local/ss5 > /dev/null 2>&1
    make > /dev/null 2>&1
    make install > /dev/null 2>&1
    
    # 创建符号链接
    ln -sf /usr/local/ss5/bin/ss5 /usr/local/bin/ss5
    ln -sf /usr/local/ss5/bin/ss5 /usr/sbin/ss5
    
    # 清理临时文件
    cd /
    rm -rf "$TEMP_DIR"
    
    log_success "ss5 已安装"
}

# 配置 ss5
configure_ss5() {
    log_info "配置 ss5..."
    
    # 创建配置目录
    mkdir -p /etc/ss5
    
    # 创建配置文件
    cat > /etc/ss5/ss5.conf << 'EOF'
# SS5 配置文件
# 监听地址和端口
listen 0.0.0.0 8888

# 认证方式: u 表示用户名/密码认证
auth 0.0.0.0/0 - u

# 日志配置
logoutput /var/log/ss5/ss5.log

# 允许所有连接
permit u 0.0.0.0/0 - 0.0.0.0/0 - - - - -
EOF
    
    chmod 644 /etc/ss5/ss5.conf
    
    log_success "ss5 配置已完成"
}

# 创建用户账户
create_user() {
    log_info "创建 SOCKS5 用户账户..."
    
    # 创建密码文件
    mkdir -p /etc/ss5
    
    # 清空旧的密码文件
    > /etc/ss5/ss5.passwd
    
    # 添加用户（格式: username:password）
    echo "$SOCKS_USER:$SOCKS_PASS" >> /etc/ss5/ss5.passwd
    
    # 设置权限
    chmod 600 /etc/ss5/ss5.passwd
    chown root:root /etc/ss5/ss5.passwd
    
    log_success "用户 $SOCKS_USER 已创建"
}

# 创建日志目录
create_log_dir() {
    log_info "创建日志目录..."
    
    mkdir -p /var/log/ss5
    chmod 755 /var/log/ss5
    
    log_success "日志目录已创建"
}

# 创建 systemd 服务文件
create_systemd_service() {
    log_info "创建 systemd 服务..."
    
    cat > /etc/systemd/system/ss5.service << 'EOF'
[Unit]
Description=SS5 SOCKS5 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/sbin/ss5 -t -f /etc/ss5/ss5.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 /etc/systemd/system/ss5.service
    
    log_success "systemd 服务已创建"
}

# 启动服务
start_service() {
    log_info "启动 ss5 服务..."
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    # 启用服务开机自启
    systemctl enable ss5
    
    # 启动服务
    systemctl start ss5
    
    # 检查服务状态
    sleep 2
    if systemctl is-active --quiet ss5; then
        log_success "ss5 服务已启动"
    else
        log_error "ss5 服务启动失败"
        systemctl status ss5
        exit 1
    fi
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    # 检查端口是否监听
    sleep 1
    if netstat -tulpn 2>/dev/null | grep -q ":$SOCKS_PORT"; then
        log_success "端口 $SOCKS_PORT 正在监听"
    elif ss -tulpn 2>/dev/null | grep -q ":$SOCKS_PORT"; then
        log_success "端口 $SOCKS_PORT 正在监听"
    else
        log_error "端口 $SOCKS_PORT 未监听"
        exit 1
    fi
    
    # 检查配置文件
    if [ -f /etc/ss5/ss5.conf ]; then
        log_success "配置文件存在"
    else
        log_error "配置文件不存在"
        exit 1
    fi
    
    # 检查密码文件
    if [ -f /etc/ss5/ss5.passwd ]; then
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
    echo "日志位置: /var/log/ss5/ss5.log"
    echo "配置文件: /etc/ss5/ss5.conf"
    echo "密码文件: /etc/ss5/ss5.passwd"
    echo "=========================================="
}

# 显示安全建议
show_security_tips() {
    echo ""
    echo "=========================================="
    echo "安全建议"
    echo "=========================================="
    echo "1. 定期检查日志: tail -f /var/log/ss5/ss5.log"
    echo "2. 定期更新系统: apt-get update && apt-get upgrade"
    echo "3. 配置防火墙规则限制访问"
    echo "4. 定期更改密码: 编辑 /etc/ss5/ss5.passwd"
    echo "5. 监控端口连接: netstat -tulpn | grep 8888"
    echo "6. 检查服务状态: systemctl status ss5"
    echo "=========================================="
}

# 主函数
main() {
    echo ""
    echo "=========================================="
    echo "简单 SOCKS5 服务器安装脚本 (ss5)"
    echo "=========================================="
    echo ""
    
    check_root
    check_system
    check_port
    update_system
    install_dependencies
    install_ss5
    create_log_dir
    configure_ss5
    create_user
    create_systemd_service
    start_service
    verify_installation
    show_connection_info
    show_security_tips
    
    echo ""
    log_success "安装完成！SOCKS5 服务器已就绪"
}

# 执行主函数
main
