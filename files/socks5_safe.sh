#!/bin/bash

#====================================================
# 简单 SOCKS5 服务器安装脚本 (Python 版本)
# 系统要求: Ubuntu/Debian
# 功能: 安装并配置轻量级 SOCKS5 服务
# 安全性: 使用 Python 实现、简单配置、无后门
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
SOCKS_DIR="/opt/socks5"
SOCKS_SERVICE="socks5"

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
        python3 \
        python3-pip \
        curl \
        wget \
        net-tools \
        lsof \
        openssl
    
    log_success "依赖包已安装"
}

# 创建 SOCKS5 服务目录
create_socks_dir() {
    log_info "创建 SOCKS5 服务目录..."
    
    mkdir -p "$SOCKS_DIR"
    mkdir -p /var/log/socks5
    
    log_success "目录已创建"
}

# 创建 Python SOCKS5 服务器脚本
create_socks5_server() {
    log_info "创建 SOCKS5 服务器脚本..."
    
    cat > "$SOCKS_DIR/socks5_server.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
import socket
import struct
import select
import sys
import logging
import os
from threading import Thread

# 配置日志
log_file = '/var/log/socks5/socks5.log'
os.makedirs(os.path.dirname(log_file), exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

# 从环境变量读取配置
SOCKS_PORT = int(os.environ.get('SOCKS_PORT', 8888))
SOCKS_USER = os.environ.get('SOCKS_USER', '8888')
SOCKS_PASS = os.environ.get('SOCKS_PASS', '8888')

class SOCKS5Server:
    def __init__(self, host='0.0.0.0', port=SOCKS_PORT):
        self.host = host
        self.port = port
        self.server_socket = None
        
    def start(self):
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(100)
        logger.info(f"SOCKS5 服务器启动在 {self.host}:{self.port}")
        
        try:
            while True:
                client_socket, client_address = self.server_socket.accept()
                logger.info(f"新连接来自 {client_address}")
                client_thread = Thread(target=self.handle_client, args=(client_socket, client_address))
                client_thread.daemon = True
                client_thread.start()
        except KeyboardInterrupt:
            logger.info("服务器关闭")
        finally:
            self.server_socket.close()
    
    def handle_client(self, client_socket, client_address):
        try:
            # 接收 SOCKS5 握手请求
            data = client_socket.recv(1024)
            if not data:
                return
            
            # 解析 SOCKS5 握手
            version = data[0]
            if version != 5:
                logger.warning(f"不支持的 SOCKS 版本: {version}")
                client_socket.close()
                return
            
            # 发送认证方法选择响应
            client_socket.send(b'\x05\x02')  # 使用用户名/密码认证
            
            # 接收认证信息
            auth_data = client_socket.recv(1024)
            if auth_data[0] != 1:  # 用户名/密码认证版本
                client_socket.close()
                return
            
            # 解析用户名和密码
            ulen = auth_data[1]
            username = auth_data[2:2+ulen].decode('utf-8')
            plen = auth_data[2+ulen]
            password = auth_data[3+ulen:3+ulen+plen].decode('utf-8')
            
            # 验证用户名和密码
            if username == SOCKS_USER and password == SOCKS_PASS:
                client_socket.send(b'\x01\x00')  # 认证成功
                logger.info(f"用户 {username} 认证成功")
            else:
                client_socket.send(b'\x01\x01')  # 认证失败
                logger.warning(f"用户 {username} 认证失败")
                client_socket.close()
                return
            
            # 接收 SOCKS5 请求
            request_data = client_socket.recv(1024)
            if not request_data:
                return
            
            # 解析请求
            version = request_data[0]
            cmd = request_data[1]
            addr_type = request_data[3]
            
            if cmd == 1:  # CONNECT 命令
                if addr_type == 1:  # IPv4
                    addr = socket.inet_ntoa(request_data[4:8])
                    port = struct.unpack('>H', request_data[8:10])[0]
                elif addr_type == 3:  # 域名
                    domain_len = request_data[4]
                    addr = request_data[5:5+domain_len].decode('utf-8')
                    port = struct.unpack('>H', request_data[5+domain_len:7+domain_len])[0]
                else:
                    client_socket.send(b'\x05\x08')  # 地址类型不支持
                    client_socket.close()
                    return
                
                logger.info(f"连接请求: {addr}:{port}")
                
                try:
                    # 连接到目标服务器
                    target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    target_socket.connect((addr, port))
                    
                    # 发送成功响应
                    response = b'\x05\x00\x00\x01'
                    response += socket.inet_aton(addr)
                    response += struct.pack('>H', port)
                    client_socket.send(response)
                    
                    logger.info(f"连接成功: {addr}:{port}")
                    
                    # 转发数据
                    self.forward_data(client_socket, target_socket)
                    
                except Exception as e:
                    logger.error(f"连接失败: {e}")
                    client_socket.send(b'\x05\x01')  # 一般 SOCKS 服务器故障
                    client_socket.close()
            else:
                client_socket.send(b'\x05\x07')  # 命令不支持
                client_socket.close()
        
        except Exception as e:
            logger.error(f"处理客户端错误: {e}")
        finally:
            client_socket.close()
    
    def forward_data(self, client_socket, target_socket):
        sockets = [client_socket, target_socket]
        
        while True:
            readable, _, _ = select.select(sockets, [], [])
            
            for sock in readable:
                if sock == client_socket:
                    data = client_socket.recv(4096)
                    if not data:
                        return
                    target_socket.send(data)
                else:
                    data = target_socket.recv(4096)
                    if not data:
                        return
                    client_socket.send(data)

if __name__ == '__main__':
    server = SOCKS5Server(port=SOCKS_PORT)
    server.start()
PYTHON_EOF
    
    chmod +x "$SOCKS_DIR/socks5_server.py"
    log_success "SOCKS5 服务器脚本已创建"
}

# 创建 systemd 服务文件
create_systemd_service() {
    log_info "创建 systemd 服务..."
    
    cat > /etc/systemd/system/socks5.service << EOF
[Unit]
Description=SOCKS5 Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SOCKS_DIR
Environment="SOCKS_PORT=$SOCKS_PORT"
Environment="SOCKS_USER=$SOCKS_USER"
Environment="SOCKS_PASS=$SOCKS_PASS"
ExecStart=/usr/bin/python3 $SOCKS_DIR/socks5_server.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 /etc/systemd/system/socks5.service
    log_success "systemd 服务已创建"
}

# 启动服务
start_service() {
    log_info "启动 SOCKS5 服务..."
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    # 启用服务开机自启
    systemctl enable socks5
    
    # 启动服务
    systemctl start socks5
    
    # 检查服务状态
    sleep 2
    if systemctl is-active --quiet socks5; then
        log_success "SOCKS5 服务已启动"
    else
        log_error "SOCKS5 服务启动失败"
        systemctl status socks5
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
    
    # 检查服务文件
    if [ -f "$SOCKS_DIR/socks5_server.py" ]; then
        log_success "服务器脚本存在"
    else
        log_error "服务器脚本不存在"
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
    echo "日志位置: /var/log/socks5/socks5.log"
    echo "服务器脚本: $SOCKS_DIR/socks5_server.py"
    echo "=========================================="
}

# 显示安全建议
show_security_tips() {
    echo ""
    echo "=========================================="
    echo "安全建议"
    echo "=========================================="
    echo "1. 定期检查日志: tail -f /var/log/socks5/socks5.log"
    echo "2. 定期更新系统: apt-get update && apt-get upgrade"
    echo "3. 配置防火墙规则限制访问"
    echo "4. 定期更改密码: 编辑 /etc/systemd/system/socks5.service"
    echo "5. 监控端口连接: netstat -tulpn | grep 8888"
    echo "6. 检查服务状态: systemctl status socks5"
    echo "=========================================="
}

# 主函数
main() {
    echo ""
    echo "=========================================="
    echo "简单 SOCKS5 服务器安装脚本 (Python 版本)"
    echo "=========================================="
    echo ""
    
    check_root
    check_system
    check_port
    update_system
    install_dependencies
    create_socks_dir
    create_socks5_server
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
