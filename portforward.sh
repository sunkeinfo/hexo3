#!/bin/bash

# ==============================================================================
# A simple and robust web interface for managing socat port forwarding
# ==============================================================================

# --- 配置 (Configuration) ---
# Web界面监听的端口
LISTEN_PORT="8080"
# 用于存储转发规则和对应PID的文件
RULES_FILE="/tmp/port_forwarding.rules"

# --- 脚本初始化 ---
# 设置更严格的错误处理
set -o errexit
set -o nounset
set -o pipefail

# 检查必要的命令是否存在
command -v socat >/dev/null 2>&1 || { echo "错误: 'socat' 命令未找到. 请先安装 (sudo apt update && sudo apt install socat -y)."; exit 1; }
command -v nc >/dev/null 2>&1 || { echo "错误: 'netcat (nc)' 命令未找到. 请先安装 (sudo apt update && sudo apt install netcat -y)."; exit 1; }

# 如果规则文件不存在，则创建它
touch "$RULES_FILE"


# ==============================================================================
# --- 核心功能函数 ---
# ==============================================================================

# URL解码函数 (处理表单提交的特殊字符)
urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# HTML页面渲染函数
# 参数 $1: 在页面顶部显示的消息 (例如成功或错误提示)
render_page() {
    local message="${1:-}" # 如果没有传入消息则为空
    
    # HTTP头
    echo -e "HTTP/1.1 200 OK"
    echo -e "Content-Type: text/html; charset=utf-8\n"

    # HTML内容
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
        input[type="text"], input[type="number"] { width: 200px; padding: 8px; margin-bottom: 10px; border: 1px solid #ccc; border-radius: 4px; }
        input[type="submit"] { background-color: #0056b3; color: white; padding: 10px 15px; border: none; border-radius: 4px; cursor: pointer; }
        input[type="submit"]:hover { background-color: #004494; }
        .rules-table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        .rules-table th, .rules-table td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        .rules-table th { background-color: #0056b3; color: white; }
        .message { padding: 10px; border-radius: 5px; margin-bottom: 20px; }
        .success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .error { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        a { color: #d9534f; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h2>端口转发管理</h2>
        
        <!-- 显示操作结果消息 -->
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
            <thead>
                <tr>
                    <th>PID</th>
                    <th>入站端口</th>
                    <th>转发至</th>
                    <th>操作</th>
                </tr>
            </thead>
            <tbody>
EOF
    # 从规则文件中读取并显示规则
    if [[ -s "$RULES_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            pid=$(echo "$line" | cut -d':' -f1)
            rule=$(echo "$line" | cut -d':' -f2-)
            inbound=$(echo "$rule" | cut -d'-' -f1 | tr -d ' ')
            destination=$(echo "$rule" | cut -d'>' -f2 | tr -d ' ')
            # 检查进程是否还在运行
            if ps -p "$pid" > /dev/null; then
                echo "<tr>"
                echo "<td>$pid</td>"
                echo "<td>$inbound</td>"
                echo "<td>$destination</td>"
                echo "<td><a href='/stop?pid=$pid' onclick=\"return confirm('确定要停止这个转发吗？');\">停止</a></td>"
                echo "</tr>"
            else
                # 如果进程已不存在，从规则文件中自动清理
                sed -i "/^${pid}:/d" "$RULES_FILE"
            fi
        done < "$RULES_FILE"
    else
        echo "<tr><td colspan='4'>暂无活动的转发规则。</td></tr>"
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
# --- 主服务器循环 ---
# ==============================================================================

echo "Web管理界面已在 http://<你的服务器IP>:${LISTEN_PORT} 上启动"

while true; do
    # 使用 netcat 作为Web服务器，-k 选项可以让它在连接结束后保持监听 (对于某些版本的nc)
    # 如果你的 nc 版本不支持 -k 或 -l, 可能需要用其他方式保持循环
    response_body=""
    message_type="success"

    # 读取HTTP请求
    {
        read -r request_line
        method=$(echo "$request_line" | awk '{print $1}')
        path=$(echo "$request_line" | awk '{print $2}')

        # 读取请求头，直到空行
        while read -r header && [ -n "$header" ]; do
            if [[ $header == "Content-Length:"* ]]; then
                content_length=$(echo "$header" | awk '{print $2}')
            fi
        done

        # 如果是POST请求，读取请求体
        if [ "$method" == "POST" ]; then
            read -r -n "${content_length:-0}" post_data
        fi

        # --- 请求路由和处理 ---

        if [[ "$method" == "POST" && "$path" == "/add" ]]; then
            # --- 添加新规则 ---
            # 解析POST数据
            eval "$(urldecode "$post_data" | sed -e 's/&/;/g')"

            # 输入验证
            if ! [[ "$inbound_port" =~ ^[0-9]+$ && "$dest_port" =~ ^[0-9]+$ && "$inbound_port" -gt 0 && "$inbound_port" -lt 65536 && "$dest_port" -gt 0 && "$dest_port" -lt 65536 ]]; then
                response_body="错误: 端口号必须是 1-65535 之间的数字。"
                message_type="error"
            elif [ -z "$dest_addr" ]; then
                response_body="错误: 目标地址不能为空。"
                message_type="error"
            else
                # 启动 socat 进程
                socat TCP-LISTEN:"$inbound_port",fork,reuseaddr TCP:"$dest_addr":"$dest_port" &
                pid=$!
                
                # 等待一小会儿并检查进程是否成功启动
                sleep 0.5
                if ps -p "$pid" > /dev/null; then
                    echo "$pid:$inbound_port -> $dest_addr:$dest_port" >> "$RULES_FILE"
                    response_body="成功: 已添加转发规则 $inbound_port -> $dest_addr:$dest_port (PID: $pid)。"
                else
                    response_body="错误: 无法在端口 $inbound_port 上启动转发。该端口可能已被占用。"
                    message_type="error"
                fi
            fi

        elif [[ "$method" == "GET" && "$path" == "/stop"* ]]; then
            # --- 停止规则 ---
            pid_to_stop=$(echo "$path" | grep -o 'pid=[0-9]*' | cut -d'=' -f2)

            if [[ "$pid_to_stop" =~ ^[0-9]+$ ]] && grep -q "^${pid_to_stop}:" "$RULES_FILE"; then
                # 验证PID确实存在于我们的规则文件中，防止误杀
                kill "$pid_to_stop"
                sed -i "/^${pid_to_stop}:/d" "$RULES_FILE"
                response_body="成功: 已停止 PID 为 $pid_to_stop 的转发进程。"
            else
                response_body="错误: 无效的PID或权限不足。"
                message_type="error"
            fi
        fi

        # 渲染并输出HTML页面
        render_page "$response_body"

    } | nc -l -k -p "$LISTEN_PORT" -q 1
    # 注意: nc的参数在不同系统上可能不同。
    # -k (keep listening) 在很多现代版本中可用。
    # 如果没有-k, 循环可能会中断。可以考虑用 socat 来做Web服务器本身，但会更复杂。
    # -q 1 使得nc在收到EOF后等待1秒再关闭，可以提高一些稳定性。
done
