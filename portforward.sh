#!/bin/bash

# 简单的Web服务器和端口转发管理脚本

# 用于存储转发规则和PID的文件
RULES_FILE="/tmp/port_forwarding_rules"
touch $RULES_FILE

# 启动Web服务器的函数
start_server() {
    while true; do
        {
            # 读取HTTP请求
            read -r request_line
            method=$(echo "$request_line" | awk '{print $1}')
            path=$(echo "$request_line" | awk '{print $2}')

            # 如果是POST请求，则读取请求体
            if [ "$method" == "POST" ]; then
                while read -r header && [ -n "$header" ]; do
                    if [[ $header == "Content-Length:"* ]]; then
                        content_length=$(echo "$header" | awk '{print $2}')
                    fi
                done
                read -r -n "$content_length" post_data
            fi

            # 生成HTTP响应
            echo -e "HTTP/1.1 200 OK"
            echo -e "Content-Type: text/html\n"

            # 处理不同的请求
            if [ "$method" == "POST" ]; then
                # 解析POST数据
                inbound_port=$(echo "$post_data" | awk -F'[=&]' '{print $2}')
                dest_addr=$(echo "$post_data" | awk -F'[=&]' '{print $4}')
                dest_port=$(echo "$post_data" | awk -F'[=&]' '{print $6}')

                # 启动socat进行端口转发，并在后台运行
                socat TCP-LISTEN:$inbound_port,fork TCP:$dest_addr:$dest_port &
                pid=$!

                # 将规则和PID存入文件
                echo "$inbound_port -> $dest_addr:$dest_port (PID: $pid)" >> $RULES_FILE
            elif [[ "$path" == "/stop"* ]]; then
                # 停止端口转发
                pid_to_stop=$(echo "$path" | cut -d'=' -f2)
                if kill "$pid_to_stop"; then
                    # 从文件中移除已停止的规则
                    sed -i "/(PID: $pid_to_stop)/d" $RULES_FILE
                fi
            fi

            # 显示Web界面
            echo "<html><head><title>端口转发设置</title></head><body>"
            echo "<h2>设置新的端口转发规则</h2>"
            echo "<form method='POST'>"
            echo "入站端口: <input type='text' name='inbound_port'><br>"
            echo "目标地址: <input type='text' name='dest_addr'><br>"
            echo "目标端口: <input type='text' name='dest_port'><br>"
            echo "<input type='submit' value='添加并保存'>"
            echo "</form>"
            echo "<h2>当前活动的转发规则</h2>"
            echo "<pre>"
            cat $RULES_FILE
            echo "</pre>"
            echo "<h3>停止规则</h3>"
            # 提供停止规则的链接
            while read -r rule; do
                pid=$(echo "$rule" | awk -F'[(:)]' '{print $3}')
                echo "<a href='/stop?pid=$pid'>停止 $rule</a><br>"
            done < $RULES_FILE
            echo "</body></html>"
        } | nc -l -p 8080 -q 1
    done
}

# 启动服务器
start_server```

### 总结

通过这个 Bash 脚本，用户可以方便地在 Ubuntu 服务器上通过网页界面来管理端口转发。这不仅简化了操作流程，也降低了手动配置可能带来的错误。对于需要频繁调整端口转发规则的开发者和系统管理员来说，这无疑是一个高效且实用的工具。
