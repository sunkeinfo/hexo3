#!/bin/bash

# ==============================================================================
# DNAT 网页控制面板一键安装脚本
# ==============================================================================

# --- 配置变量 ---
# 你可以在这里修改安装路径和端口号
INSTALL_DIR="/opt/dnat-dashboard"
APP_FILE="$INSTALL_DIR/app.py"
TEMPLATES_DIR="$INSTALL_DIR/templates"
HTML_FILE="$TEMPLATES_DIR/index.html"
PORT=5000
SERVICE_NAME="dnat-dashboard"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# --- 脚本函数 ---

# 检查是否以 root 身份运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "错误：此脚本必须以 root 身份运行。"
        exit 1
    fi
}

# 安装系统依赖
install_dependencies() {
    echo "--- [1/4] 正在安装系统依赖... ---"
    
    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        apt-get update >/dev/null
        apt-get install -y python3 python3-pip >/dev/null
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        yum install -y python3 python3-pip >/dev/null
    else
        echo "错误：无法确定包管理器。请手动安装 Python 3 和 pip。"
        exit 1
    fi

    # 安装 Flask
    pip3 install Flask >/dev/null
    
    echo "依赖安装完成。"
    echo
}

# 创建 Flask 后端应用
create_flask_app() {
    echo "--- [2/4] 正在创建后端应用 (app.py)... ---"
    
    mkdir -p "$INSTALL_DIR"
    
    # 使用 heredoc 创建 app.py 文件
    cat <<EOF > "$APP_FILE"
from flask import Flask, render_template, request, jsonify
import subprocess
import os

app = Flask(__name__)

# 定义脚本和配置文件的路径
BASE_PATH = "/etc/dnat"
CONF_FILE = os.path.join(BASE_PATH, "conf")

# 确保基础目录和配置文件存在
if not os.path.exists(BASE_PATH):
    os.makedirs(BASE_PATH)
if not os.path.exists(CONF_FILE):
    open(CONF_FILE, 'a').close()

def run_command(command):
    """执行 shell 命令并返回输出"""
    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return {"success": True, "output": result.stdout}
    except subprocess.CalledProcessError as e:
        return {"success": False, "error": e.stderr}

@app.route('/')
def index():
    """渲染主页面"""
    return render_template('index.html')

@app.route('/api/rules', methods=['GET'])
def get_rules():
    """获取所有转发规则"""
    try:
        with open(CONF_FILE, 'r') as f:
            rules = f.read().strip().split('\n')
            # 过滤掉空行
            rules = [rule for rule in rules if rule]
        return jsonify({"success": True, "rules": rules})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})

@app.route('/api/rules', methods=['POST'])
def add_rule():
    """增加一条转发规则"""
    data = request.json
    local_port = data.get('local_port')
    remote_host = data.get('remote_host')
    remote_port = data.get('remote_port')

    if not all([local_port, remote_host, remote_port]):
        return jsonify({"success": False, "error": "所有字段都是必填项。"})

    # 为了避免重复，先尝试删除旧的规则
    run_command(f"sed -i '/^{local_port}>.*/d' {CONF_FILE}")

    # 追加新规则
    new_rule = f"{local_port}>{remote_host}:{remote_port}"
    with open(CONF_FILE, 'a') as f:
        f.write(new_rule + '\n')

    # 重新启动服务以应用更改 (如果 dnat 服务存在)
    run_command("systemctl restart dnat &> /dev/null")

    return jsonify({"success": True, "message": f"规则 '{new_rule}' 已成功添加。"})

@app.route('/api/rules/delete', methods=['POST'])
def delete_rule():
    """删除一条转发规则"""
    data = request.json
    local_port = data.get('local_port')

    if not local_port:
        return jsonify({"success": False, "error": "需要提供本地端口。"})

    result = run_command(f"sed -i '/^{local_port}>.*/d' {CONF_FILE}")

    if result["success"]:
        # 重新启动服务以应用更改 (如果 dnat 服务存在)
        run_command("systemctl restart dnat &> /dev/null")
        return jsonify({"success": True, "message": f"所有使用本地端口 '{local_port}' 的规则都已被删除。"})
    else:
        return jsonify({"success": False, "error": result["error"]})

@app.route('/api/iptables', methods=['GET'])
def get_iptables():
    """获取当前的 iptables 配置"""
    prerouting = run_command("iptables -L PREROUTING -n -t nat --line-number")
    postrouting = run_command("iptables -L POSTROUTING -n -t nat --line-number")

    if prerouting["success"] and postrouting["success"]:
        return jsonify({
            "success": True,
            "prerouting": prerouting["output"],
            "postrouting": postrouting["output"]
        })
    else:
        error_msg = f"PREROUTING Error: {prerouting.get('error', 'N/A')}\\nPOSTROUTING Error: {postrouting.get('error', 'N/A')}"
        return jsonify({"success": False, "error": error_msg})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=${PORT})
EOF
    
    echo "后端应用创建完成。"
    echo
}

# 创建 HTML 前端页面
create_html_template() {
    echo "--- [3/4] 正在创建前端页面 (index.html)... ---"

    mkdir -p "$TEMPLATES_DIR"

    # 使用 heredoc 创建 index.html 文件, 注意使用 'EOF' 防止 shell 扩展 $ 符号
    cat <<'EOF' > "$HTML_FILE"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNAT 规则控制面板</title>
    <!-- 引入 Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { padding: 20px; }
        .container { max-width: 800px; }
        .output { background-color: #f8f9fa; border: 1px solid #dee2e6; padding: 15px; margin-top: 20px; white-space: pre-wrap; font-family: monospace; }
        .card-header .btn { margin-top: -5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="mb-4">DNAT 规则控制面板</h1>

        <!-- 添加规则表单 -->
        <div class="card mb-4">
            <div class="card-header">增加/修改转发规则</div>
            <div class="card-body">
                <form id="add-rule-form">
                    <div class="row g-3 align-items-end">
                        <div class="col-md-3"><label for="local_port" class="form-label">本地端口</label><input type="number" class="form-control" id="local_port" placeholder="例如: 8080" required></div>
                        <div class="col-md-5"><label for="remote_host" class="form-label">目标域名/IP</label><input type="text" class="form-control" id="remote_host" placeholder="例如: example.com" required></div>
                        <div class="col-md-3"><label for="remote_port" class="form-label">目标端口</label><input type="number" class="form-control" id="remote_port" placeholder="例如: 80" required></div>
                        <div class="col-md-1"><button type="submit" class="btn btn-primary w-100">添加</button></div>
                    </div>
                </form>
            </div>
        </div>

        <!-- 当前规则列表 -->
        <div class="card mb-4">
            <div class="card-header">当前转发规则<button class="btn btn-sm btn-secondary float-end" onclick="loadRules()">刷新</button></div>
            <div class="card-body"><ul class="list-group" id="rules-list"></ul></div>
        </div>

        <!-- 查看 iptables 配置 -->
        <div class="card">
            <div class="card-header">当前 Iptables 配置 (nat 表)<button class="btn btn-sm btn-secondary float-end" onclick="loadIptables()">刷新</button></div>
            <div class="card-body">
                <h5>PREROUTING 链</h5><pre class="output" id="prerouting-output">点击刷新按钮查看...</pre>
                <h5 class="mt-3">POSTROUTING 链</h5><pre class="output" id="postrouting-output">点击刷新按钮查看...</pre>
            </div>
        </div>
    </div>

    <!-- 引入 jQuery 和 Bootstrap JS -->
    <script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
    <script>
        $(document).ready(function() {
            loadRules();
            $('#add-rule-form').submit(function(e) {
                e.preventDefault();
                const rule = { local_port: $('#local_port').val(), remote_host: $('#remote_host').val(), remote_port: $('#remote_port').val() };
                $.ajax({
                    url: '/api/rules', type: 'POST', contentType: 'application/json', data: JSON.stringify(rule),
                    success: function(response) {
                        alert(response.success ? response.message : '错误: ' + response.error);
                        if(response.success) { loadRules(); $('#add-rule-form')[0].reset(); }
                    },
                    error: function() { alert('请求失败，请检查后端服务是否正常。'); }
                });
            });
        });

        function loadRules() {
            $.get('/api/rules', function(response) {
                const list = $('#rules-list').empty();
                if (response.success && response.rules.length > 0) {
                    response.rules.forEach(rule => {
                        const local_port = rule.split('>')[0];
                        list.append(`<li class="list-group-item d-flex justify-content-between align-items-center">${rule}<button class="btn btn-danger btn-sm" onclick="deleteRule('${local_port}')">删除</button></li>`);
                    });
                } else {
                    list.append(`<li class="list-group-item">${response.success ? '暂无规则' : '加载规则失败: ' + response.error}</li>`);
                }
            });
        }

        function deleteRule(local_port) {
            if (!confirm(`确定要删除所有使用本地端口 ${local_port} 的规则吗?`)) return;
            $.ajax({
                url: '/api/rules/delete', type: 'POST', contentType: 'application/json', data: JSON.stringify({ local_port: local_port }),
                success: function(response) {
                    alert(response.success ? response.message : '错误: ' + response.error);
                    if(response.success) loadRules();
                },
                error: function() { alert('请求失败，请检查后端服务是否正常。'); }
            });
        }

        function loadIptables() {
            $('#prerouting-output, #postrouting-output').text('加载中...');
            $.get('/api/iptables', function(response) {
                if (response.success) {
                    $('#prerouting-output').text(response.prerouting || '无输出');
                    $('#postrouting-output').text(response.postrouting || '无输出');
                } else {
                    $('#prerouting-output').text('加载失败: ' + response.error);
                    $('#postrouting-output').text('加载失败');
                }
            });
        }
    </script>
</body>
</html>
EOF

    echo "前端页面创建完成。"
    echo
}

# 创建并启动 systemd 服务
create_systemd_service() {
    echo "--- [4/4] 正在创建并启动 systemd 服务... ---"

    # 创建 systemd 服务文件
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=DNAT Web Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $APP_FILE
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载、启用并启动服务
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    systemctl restart "$SERVICE_NAME"

    # 等待一秒钟让服务启动
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "服务 '$SERVICE_NAME' 已成功启动并设置为开机自启。"
    else
        echo "错误：服务 '$SERVICE_NAME' 启动失败。请使用以下命令检查日志："
        echo "journalctl -u $SERVICE_NAME"
    fi
    echo
}

# --- 主函数 ---
main() {
    check_root
    install_dependencies
    create_flask_app
    create_html_template
    create_systemd_service

    # 获取服务器 IP 地址
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    echo "==================================================================="
    echo "🎉 DNAT 网页控制面板安装完成！"
    echo
    echo "您现在可以通过浏览器访问以下地址来管理您的 DNAT 规则："
    echo "   http://${IP_ADDR}:${PORT}"
    echo
    echo "如果无法访问，请确保您的防火墙已放行 ${PORT} 端口。"
    echo "==================================================================="
    echo
    echo "服务管理命令:"
    echo "  - 查看状态: systemctl status ${SERVICE_NAME}"
    echo "  - 启动服务: systemctl start ${SERVICE_NAME}"
    echo "  - 停止服务: systemctl stop ${SERVICE_NAME}"
    echo "  - 查看日志: journalctl -u ${SERVICE_NAME} -f"
    echo
}

# --- 执行脚本 ---
main
