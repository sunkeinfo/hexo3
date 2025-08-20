#!/bin/bash

# ==============================================================================
# All-in-One Installer for Nginx + Python Web Port Forwarding Manager (v2)
# ==============================================================================
# This script will:
# 1. Check for root privileges.
# 2. Install Nginx, Python3, pip, and venv using a more robust command.
# 3. Configure Nginx for web hosting and TCP stream proxying.
# 4. Create a Python Flask backend API.
# 5. Create a systemd service to run the API persistently.
# 6. Create the HTML/CSS/JS frontend.
# 7. Grant necessary sudo permissions safely.
# 8. Configure UFW firewall.
# 9. Start and enable all services.
# ==============================================================================

# --- Safety First ---
set -e
set -u
set -o pipefail

# --- Helper Functions for colored output ---
log_info() {
    echo -e "\n\e[1;34m[INFO]\e[0m $1"
}

log_success() {
    echo -e "\e[1;32m[SUCCESS]\e[0m $1"
}

log_error() {
    echo -e "\e[1;31m[ERROR]\e[0m $1" >&2
}

# --- Root Check ---
if [ "$(id -u)" -ne 0 ]; then
   log_error "This script must be run as root. Please use 'sudo bash'."
   exit 1
fi

# --- Main Functions ---

install_dependencies() {
    log_info "Updating package lists... (This may take a moment)"
    apt-get update -y
    
    log_info "Installing/Verifying Nginx, Python3, pip, and venv with --fix-broken..."
    # Using -fy to attempt to fix any broken dependencies during installation.
    apt-get install -fy nginx python3 python3-pip python3-venv
    
    # Explicitly check if nginx service is now available
    if ! systemctl list-units --type=service | grep -q "nginx.service"; then
        log_error "Nginx installation failed. The 'nginx.service' unit was not found after installation attempt."
        log_error "Please try running 'sudo apt-get update && sudo apt-get install -fy nginx' manually to diagnose the issue."
        exit 1
    fi
    log_success "Dependencies installed and verified."
}

configure_nginx() {
    log_info "Configuring Nginx..."

    mkdir -p /etc/nginx/tcp.d

    if ! grep -q "include /etc/nginx/tcp.d/\*.conf;" /etc/nginx/nginx.conf; then
        log_info "Adding TCP stream configuration to nginx.conf."
        echo -e '\nstream {\n    include /etc/nginx/tcp.d/*.conf;\n}' >> /etc/nginx/nginx.conf
    else
        log_info "TCP stream configuration already exists in nginx.conf."
    fi

    log_info "Creating Nginx site configuration for the web panel."
    cat > /etc/nginx/sites-available/port-manager << 'EOF'
server {
    listen 80;
    server_name _;

    root /var/www/port-manager;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location /api {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

    ln -sfn /etc/nginx/sites-available/port-manager /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    log_info "Testing Nginx configuration..."
    nginx -t
    log_success "Nginx configured successfully."
}

create_backend_api() {
    log_info "Creating Python Flask backend API..."
    
    mkdir -p /opt/port-manager-api
    python3 -m venv /opt/port-manager-api/venv
    
    /opt/port-manager-api/venv/bin/pip install Flask
    
    cat > /opt/port-manager-api/app.py << 'EOF'
import os
import subprocess
from flask import Flask, request, jsonify

app = Flask(__name__)
TCP_CONFIG_DIR = "/etc/nginx/tcp.d"

def reload_nginx():
    """Tests Nginx configuration and then reloads it. Returns (status, message)."""
    try:
        # Use subprocess.run with check=True to automatically raise an exception on non-zero exit codes.
        subprocess.run(['sudo', 'nginx', '-t'], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        # The stderr from nginx -t is the most useful error message.
        return False, f"Nginx configuration error: {e.stderr.strip()}"
    
    try:
        subprocess.run(['sudo', 'systemctl', 'reload', 'nginx'], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        return False, f"Failed to reload Nginx: {e.stderr.strip()}"
        
    return True, "Nginx reloaded successfully."

@app.route('/api/rules', methods=['GET'])
def get_rules():
    """Lists all current forwarding rules."""
    if not os.path.exists(TCP_CONFIG_DIR):
        return jsonify([]) # Return empty list if dir doesn't exist
    rules = []
    for filename in sorted(os.listdir(TCP_CONFIG_DIR)):
        if filename.endswith(".conf"):
            rules.append({"id": filename, "name": filename.replace('.conf', '')})
    return jsonify(rules)

@app.route('/api/add', methods=['POST'])
def add_rule():
    """Adds a new forwarding rule."""
    data = request.json
    inbound_port = data.get('inbound_port')
    dest_addr = data.get('dest_addr')
    dest_port = data.get('dest_port')

    if not all([inbound_port, dest_addr, dest_port]):
        return jsonify({"error": "Missing required fields."}), 400
    if not (str(inbound_port).isdigit() and str(dest_port).isdigit() and 1 <= int(inbound_port) <= 65535 and 1 <= int(dest_port) <= 65535):
        return jsonify({"error": "Ports must be a number between 1 and 65535."}), 400

    filename = f"rule_{inbound_port}.conf"
    filepath = os.path.join(TCP_CONFIG_DIR, filename)
    
    if os.path.exists(filepath):
        return jsonify({"error": f"Rule for inbound port {inbound_port} already exists."}), 409

    # Using a structured format for clarity and security
    config_content = f"server {{\n    listen {inbound_port};\n    proxy_pass {dest_addr}:{dest_port};\n}}"
    
    try:
        with open(filepath, 'w') as f:
            f.write(config_content)
    except IOError as e:
        return jsonify({"error": f"Failed to write config file: {e}"}), 500

    success, message = reload_nginx()
    if not success:
        os.remove(filepath) # Rollback: remove the bad config file
        return jsonify({"error": message}), 500
        
    return jsonify({"success": True, "message": f"Rule for port {inbound_port} added."}), 201

@app.route('/api/delete', methods=['POST'])
def delete_rule():
    """Deletes a forwarding rule."""
    data = request.json
    filename = data.get('id')

    # Basic security check against directory traversal
    if not filename or not filename.endswith(".conf") or '/' in filename:
        return jsonify({"error": "Invalid filename provided."}), 400
        
    filepath = os.path.join(TCP_CONFIG_DIR, filename)

    if not os.path.exists(filepath):
        return jsonify({"error": "Rule not found."}), 404
        
    os.remove(filepath)
    
    success, message = reload_nginx()
    if not success:
        # The file is already deleted, but we should still report the Nginx reload error.
        return jsonify({"error": f"File deleted, but failed to reload Nginx: {message}"}), 500

    return jsonify({"success": True, "message": f"Rule {filename} deleted."})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF
    log_success "Backend API created."
}

create_systemd_service() {
    log_info "Creating systemd service for the backend API..."
    cat > /etc/systemd/system/port-manager.service << 'EOF'
[Unit]
Description=Port Manager API for Nginx
After=network.target

[Service]
# Running as root is simpler for sudo access needed by the app.
# For higher security, run as a dedicated user and configure sudoers for that user.
User=root
Group=www-data
WorkingDirectory=/opt/port-manager-api
ExecStart=/opt/port-manager-api/venv/bin/python app.py
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    log_success "Systemd service file created."
}

create_frontend() {
    log_info "Creating frontend web interface..."
    mkdir -p /var/www/port-manager
    
    cat > /var/www/port-manager/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nginx 端口转发管理</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background-color: #f8f9fa; color: #212529; margin: 0; padding: 2rem; }
        .container { max-width: 900px; margin: auto; background: #fff; padding: 2rem; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        h1, h2 { color: #007bff; border-bottom: 2px solid #dee2e6; padding-bottom: 0.5rem; }
        form { margin-bottom: 2rem; padding: 1.5rem; background-color: #e9ecef; border-radius: 6px; display: flex; flex-wrap: wrap; align-items: flex-end; gap: 1rem; }
        .form-group { flex: 1; min-width: 200px; }
        label { display: block; margin-bottom: 0.5rem; font-weight: bold; }
        input[type="text"], input[type="number"] { width: 100%; box-sizing: border-box; padding: 10px; border: 1px solid #ced4da; border-radius: 4px; font-size: 1rem; }
        button { padding: 10px 20px; font-size: 1rem; color: #fff; background-color: #007bff; border: none; border-radius: 4px; cursor: pointer; transition: background-color 0.2s; white-space: nowrap; }
        button:hover { background-color: #0056b3; }
        button:disabled { background-color: #6c757d; cursor: not-allowed; }
        table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
        th, td { padding: 12px; border-bottom: 1px solid #dee2e6; text-align: left; }
        th { background-color: #f2f2f2; }
        .delete-btn { background-color: #dc3545; }
        .delete-btn:hover { background-color: #c82333; }
        .message { padding: 1rem; margin-bottom: 1rem; border-radius: 4px; font-weight: bold; }
        .success { background-color: #d4edda; color: #155724; }
        .error { background-color: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Nginx 端口转发管理</h1>
        <div id="message-area"></div>
        
        <h2>添加新规则</h2>
        <form id="add-rule-form">
            <div class="form-group"><label for="inbound_port">入站端口</label><input type="number" id="inbound_port" placeholder="例如: 8888" required></div>
            <div class="form-group"><label for="dest_addr">目标地址</label><input type="text" id="dest_addr" placeholder="IP或域名" required></div>
            <div class="form-group"><label for="dest_port">目标端口</label><input type="number" id="dest_port" placeholder="例如: 80" required></div>
            <button type="submit">添加规则</button>
        </form>

        <h2>当前规则</h2>
        <table id="rules-table">
            <thead><tr><th>规则名称</th><th>操作</th></tr></thead>
            <tbody></tbody>
        </table>
    </div>

    <script>
        const API_BASE = '/api';
        const form = document.getElementById('add-rule-form');
        const tableBody = document.querySelector('#rules-table tbody');
        const messageArea = document.getElementById('message-area');

        function showMessage(text, type) {
            messageArea.innerHTML = `<div class="message ${type}">${text}</div>`;
            setTimeout(() => messageArea.innerHTML = '', 5000);
        }

        async function fetchRules() {
            try {
                const response = await fetch(`${API_BASE}/rules`);
                const rules = await response.json();
                tableBody.innerHTML = '';
                if (rules.length === 0) {
                    tableBody.innerHTML = '<tr><td colspan="2">暂无转发规则。</td></tr>';
                } else {
                    rules.forEach(rule => {
                        tableBody.innerHTML += `<tr><td>${rule.name}</td><td><button class="delete-btn" onclick="deleteRule('${rule.id}')">删除</button></td></tr>`;
                    });
                }
            } catch (error) {
                showMessage(`加载规则失败: ${error}`, 'error');
            }
        }

        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            const data = {
                inbound_port: document.getElementById('inbound_port').value,
                dest_addr: document.getElementById('dest_addr').value,
                dest_port: document.getElementById('dest_port').value
            };
            const submitButton = form.querySelector('button');
            submitButton.disabled = true;
            submitButton.textContent = '添加中...';

            try {
                const response = await fetch(`${API_BASE}/add`, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(data)
                });
                const result = await response.json();
                if (!response.ok) throw new Error(result.error || '未知错误');
                
                showMessage(result.message || '规则添加成功!', 'success');
                form.reset();
                fetchRules();
            } catch (error) {
                showMessage(`添加失败: ${error.message}`, 'error');
            } finally {
                submitButton.disabled = false;
                submitButton.textContent = '添加规则';
            }
        });

        async function deleteRule(ruleId) {
            if (!confirm(`确定要删除规则 ${ruleId} 吗？`)) return;
            
            try {
                const response = await fetch(`${API_BASE}/delete`, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ id: ruleId })
                });
                const result = await response.json();
                if (!response.ok) throw new Error(result.error || '未知错误');

                showMessage(result.message || '规则删除成功!', 'success');
                fetchRules();
            } catch (error) {
                showMessage(`删除失败: ${error.message}`, 'error');
            }
        }

        document.addEventListener('DOMContentLoaded', fetchRules);
    </script>
</body>
</html>
EOF
    log_success "Frontend web interface created."
}

setup_sudoers() {
    log_info "Setting up sudo permissions for the API..."
    # The API service runs as root, so it already has permissions.
    # This file ensures that even if you change the service user,
    # it can still perform the required actions without a password prompt.
    cat > /etc/sudoers.d/99-port-manager << 'EOF'
Defaults:root !requiretty
root ALL=(ALL) NOPASSWD: /usr/sbin/nginx -t
root ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx
EOF
    chmod 0440 /etc/sudoers.d/99-port-manager
    log_success "Sudo permissions configured."
}

configure_firewall() {
    log_info "Configuring firewall (UFW)..."
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 22/tcp
        ufw allow 80/tcp
        
        # Enable UFW if it's not already active
        if ! ufw status | grep -q "Status: active"; then
            ufw --force enable
        fi
        log_success "Firewall configured to allow SSH (22) and HTTP (80)."
    else
        log_info "UFW not found. Skipping firewall configuration. Please configure your firewall manually."
    fi
}

start_services() {
    log_info "Enabling and starting services..."
    systemctl daemon-reload
    systemctl enable port-manager.service
    systemctl start port-manager.service
    systemctl restart nginx
    log_success "All services are running."
}

# --- Script Execution ---
main() {
    install_dependencies
    configure_nginx
    create_backend_api
    create_systemd_service
    create_frontend
    setup_sudoers
    start_services
    configure_firewall
    
    # Use 'ip a' or 'hostname -I' as a fallback if curl fails.
    PUBLIC_IP=$(hostname -I | awk '{print $1}' || echo "YOUR_SERVER_IP")
    
    echo -e "\n\n\e[1;32m=============================================================="
    echo -e "          INSTALLATION COMPLETE!          "
    echo -e "==============================================================\e[0m"
    echo -e "Your Port Forwarding Manager is now running."
    echo -e "Access it at: \e[1;33mhttp://${PUBLIC_IP}\e[0m"
    echo -e "\n\e[1;31mIMPORTANT:\e[0m The firewall has allowed port 80 (for the panel) and 22 (for SSH)."
    echo -e "For every new forwarding rule you create (e.g., for port 8888),"
    echo -e "you MUST manually open that port in the firewall:"
    echo -e "Example: \e[1;36msudo ufw allow 8888\e[0m"
    echo -e "You may also need to open these ports in your cloud provider's security group."
}

# Run the main function
main
