#!/bin/bash

# ==============================================================================
# A self-installing web interface for managing socat port forwarding
# ==============================================================================

# --- 配置 (Configuration) ---
LISTEN_PORT="8080"
RULES_FILE="/tmp/port_forwarding.rules"

# --- 脚本初始化 ---
set -o errexit
set -o nounset
set -o pipefail

# ==============================================================================
# --- 自动安装依赖 ---
# ==============================================================================

function check_and_install_dependencies() {
    local needs_update=false
    local packages_to_install=""
    
    # 检查 socat
    if ! command -v socat >/dev/null 2>&1; then
        echo "'socat' 未找到. 将其加入安装列表."
        packages_to_install+=" socat"
        needs_update=true
    fi

    # 检查 netcat (nc)
    if ! command -v nc >/dev/null 2>&1; then
        echo "'netcat (nc)' 未找到. 将其加入安装列表."
        # 我们优先安装 netcat-openbsd 因为它功能更全
        packages_to_install+=" netcat-openbsd"
        needs_update=true
    fi

    # 如果有需要安装的包
    if [ -n "$packages_to_install" ]; then
        echo "正在安装必要的软件: $packages_to_install"
        
        # 判断是否需要 sudo
        local SUDO_CMD=""
        if [ "$(id -u)" -ne 0 ]; then
            if ! command -v sudo >/dev/null 2>&1; then
                echo "错误: 此脚本需要 root 权限来安装软件, 并且 'sudo' 命令未找到." >&2
                exit 1
            fi
            SUDO_CMD="sudo"
        fi

        # 执行安装
        # 首先更新 apt 列表，然后安装
        echo "正在运行 apt-get update..."
        $SUDO_CMD apt-get update -y
        
        echo "正在安装 $packages_to_install..."
        $SUDO_CMD apt-get install -y $packages_to_install

        echo "依赖安装完成."
    else
        echo "所有必要的依赖均已安装."
    fi
}


# ==============================================================================
# --- 核心功能函数 (与之前版本相同) ---
# ==============================================================================

# URL解码函数
urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# HTML页面渲染函数
render_page() {
    local message="${1:-}"
    
    echo -e "HTTP/1.1 200 OK"
    echo -e "Content-Type: text/html; charset=utf-8\n"

    cat << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>端口转发管理</title>
    <style>
        body { font-family: sans-serif; background-color: #f4f4f9; color: #333; margin: 2em; }
        .container { max-width: 800px; margin: auto; background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h2, h3 { color: #0056b3; }
        input[type="text"], input[type="number"] { width: 95%; padding: 8px; margin-bottom: 10px; border: 1px solid #ccc; border-radius: 4px; }
        input[type="submit"] { background-color: #0056b3; color: white; padding: 10px 15px; border: none; border-radius: 4px; cursor: pointer; }
        input[type="submit"]:hover { background-color: #004494; }
        .rules-table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        .rules-table th, .rules-table td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        .rules-table th { background-color: #0056b3; color: white; }
        .message { padding: 10px; border-radius: 5px; margin-bottom: 20px; word-wrap: break-word; }
        .success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .error { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        a.stop-link { color: #d9534f; text-decoration: none; font-weight: bold; }
        a.stop-link:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h2>端口转发管理</h2>
        
        [[ -n "\$message" ]] && echo "<div class='message \${message_type}'>\$message</div>"

        <h3><span style="font-size: 1.5em;">&#43;</span> 添加新规则</h3>
        <form method="POST" action="/add">
            入站端口: <br><input type="number" name="inbound_port" placeholder="例如: 8888" required><br>
            目标地址: <br><input type="text" name="dest_addr" placeholder="例如: 192.168.1.100 或 example.com" required><br>
            目标端口: <br><input type="number" name="dest_port" placeholder="例如: 80" required><br>
            <input type="submit" value="添加转发">
        </form>

        <h3><span style="font-size: 1.2em;">&#128279;</span> 当前活动的转发规则</h3>
        <table class="rules-table">
            <thead><tr><th>PID</th><th>入站端口</th><th>转发至</th><th>操作</th></tr></thead>
            <tbody>
EOF
    if [[ -s "$RULES_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            pid=$(echo "$line" | cut -d':' -f1)
            rule=$(echo "$line" | cut -d':' -f2-)
            if ps -p "$pid" > /dev/null; then
                inbound=$(echo "$rule" | cut -d'-' -f1 | tr -d ' ')
                destination=$(echo "$rule" | cut -d'>' -f2 | tr -d ' ')
                echo "<tr><td>$pid</td><td>$inbound</td><td>$destination</td><td><a href='/stop?pid=$pid' class='stop-link' onclick=\"return confirm('确定要停止这个转发吗？');\">停止</a></td></tr>"
            else
                sed -i "/^${pid}:/d" "$RULES_FILE"
            fi
        done < "$RULES_FILE"
    else
        echo "<tr><td colspan='4' style='text-align:center;'>暂无活动的转发规则。</td></tr>"
    fi

    cat << EOF
            </tbody>
        </table>
    </div>
</body>
</html>
EOF
}


# ==============================================================================
# --- 主程序入口 ---
# ==============================================================================

# 1. 检查并安装依赖
check_and_install_dependencies

# 2. 创建规则文件 (如果不存在)
touch "$RULES_FILE"

# 3. 启动Web服务器主循环
echo "Web管理界面已在 http://<你的服务器IP>:${LISTEN_PORT} 上启动"
while true; do
    response_body=""
    message_type="success"

    {
        read -r request_line
        method=$(echo "$request_line" | awk '{print $1}')
        path=$(echo "$request_line" | awk '{print $2}')

        while read -r header && [ -n "$header" ]; do
            if [[ $header == "Content-Length:"* ]]; then
                content_length=$(echo "$header" | awk '{print $2}')
            fi
        done

        if [ "$method" == "POST" ]; then
            read -r -n "${content_length:-0}" post_data
        fi

        if [[ "$method" == "POST" && "$path" == "/add" ]]; then
            eval "$(urldecode "$post_data" | sed -e 's/&/;/g')"
            if ! [[ "${inbound_port:-}" =~ ^[0-9]+$ && "${dest_port:-}" =~ ^[0-9]+$ && "$inbound_port" -gt 0 && "$inbound_port" -lt 65536 && "$dest_port" -gt 0 && "$dest_port" -lt 65536 ]]; then
                response_body="错误: 端口号必须是 1-65535 之间的数字。"
                message_type="error"
            elif [ -z "${dest_addr:-}" ]; then
                response_body="错误: 目标地址不能为空。"
                message_type="error"
            else
                socat TCP-LISTEN:"$inbound_port",fork,reuseaddr TCP:"$dest_addr":"$dest_port" &
                pid=$!
                sleep 0.5
                if ps -p "$pid" > /dev/null; then
                    echo "$pid:$inbound_port -> $dest_addr:$dest_port" >> "$RULES_FILE"
                    response_body="成功: 已添加转发规则 $inbound_port -> $dest_addr:$dest_port (PID: $pid)。"
                else
                    response_body="错误: 无法在端口 $inbound_port 上启动转发。该端口可能已被占用或地址无效。"
                    message_type="error"
                fi
            fi
        elif [[ "$method" == "GET" && "$path" == "/stop"* ]]; then
            pid_to_stop=$(echo "$path" | grep -o 'pid=[0-9]*' | cut -d'=' -f2)
            if [[ "$pid_to_stop" =~ ^[0-9]+$ ]] && grep -q "^${pid_to_stop}:" "$RULES_FILE"; then
                kill "$pid_to_stop"
                sed -i "/^${pid_to_stop}:/d" "$RULES_FILE"
                response_body="成功: 已停止 PID 为 $pid_to_stop 的转发进程。"
            else
                response_body="错误: 无效的PID或权限不足。"
                message_type="error"
            fi
        fi

        render_page "$response_body"
    } | nc -l -k -p "$LISTEN_PORT" -q 1
done
