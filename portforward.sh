#!/bin/bash

# ==============================================================================
# Definitive All-in-One Installer for Nginx + Python Port Forwarding Manager (v3)
# ==============================================================================
# This script is designed to be robust and idempotent. It can be run multiple
# times to ensure the system is in the correct state.
#
# It fixes all previously identified issues, including:
#   - Ensuring dependencies are correctly installed and services exist.
#   - Forcefully correcting Nginx site configurations to prevent default page issues.
#   - Verifying each critical step before proceeding.
# ==============================================================================

# --- Script Setup ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error.
set -u
# Pipe commands should fail if any command in the pipe fails.
set -o pipefail

# --- Helper Functions for Logging ---
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
    log_info "Updating package lists..."
    apt-get update -y
    
    log_info "Installing dependencies with --fix-broken to ensure stability..."
    # This command attempts to fix any broken dependencies during installation.
    apt-get install -fy nginx python3 python3-pip python3-venv
    
    # CRITICAL VERIFICATION: Check if the nginx service was actually installed.
    # This was a major failure point in previous attempts.
    if ! systemctl list-units --type=service | grep -q "nginx.service"; then
        log_error "Nginx installation failed. The 'nginx.service' unit was not found."
        log_error "Please run 'sudo apt-get update && sudo apt-get install -fy nginx' manually to diagnose."
        exit 1
    fi
    log_success "Dependencies installed and verified."
}

configure_nginx() {
    log_info "Configuring Nginx..."

    mkdir -p /etc/nginx/tcp.d

    if ! grep -q "stream {" /etc/nginx/nginx.conf; then
        log_info "Adding TCP stream configuration to nginx.conf."
        echo -e '\nstream {\n    include /etc/nginx/tcp.d/*.conf;\n}' >> /etc/nginx/nginx.conf
    else
        log_info "TCP stream configuration already present."
    fi

    log_info "Creating Nginx site configuration file..."
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

    log_info "Ensuring correct site is enabled by cleaning and re-linking..."
    # This is the definitive fix for the "Welcome to nginx!" issue.
    # We remove both potential links and create only the one we need.
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-enabled/port-manager
    ln -s /etc/nginx/sites-available/port-manager /etc/nginx/sites-enabled/

    # CRITICAL VERIFICATION: Check that the symlink is correct.
    if [ ! -L "/etc/nginx/sites-enabled/port-manager" ] || [ "$(readlink -f /etc/nginx/sites-enabled/port-manager)" != "/etc/nginx/sites-available/port-manager" ]; then
        log_error "Failed to create or verify the Nginx site symlink."
        exit 1
    fi
    log_success "Nginx site correctly enabled."

    log_info "Testing final Nginx configuration..."
    nginx -t
    log_success "Nginx configuration is valid."
}

create_backend_api() {
    log_info "Setting up Python Flask backend API..."
    
    mkdir -p /opt/port-manager-api
    if [ ! -d "/opt/port-manager-api/venv" ]; then
        python3 -m venv /opt/port-manager-api/venv
    fi
    
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
        subprocess.run(['nginx', '-t'], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        return False, f"Nginx configuration error: {e.stderr.strip()}"
    
    try:
        subprocess.run(['systemctl', 'reload', 'nginx'], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        return False, f"Failed to reload Nginx: {e.stderr.strip()}"
        
    return True, "Nginx reloaded successfully."

@app.route('/api/rules', methods=['GET'])
def get_rules():
    if not os.path.exists(TCP_CONFIG_DIR):
        return jsonify([])
    rules = []
    for filename in sorted(os.listdir(TCP_CONFIG_DIR)):
        if filename.endswith(".conf"):
            rules.append({"id": filename, "name": filename.replace('.conf', '')})
    return jsonify(rules)

@app.route('/api/add', methods=['POST'])
def add_rule():
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

    config_content = f"server {{\n    listen {inbound_port};\n    proxy_pass {dest_addr}:{dest_port};\n}}"
    
    try:
        with open(filepath, 'w') as f:
            f.write(config_content)
    except IOError as e:
        return jsonify({"error": f"Failed to write config file: {e}"}), 500

    success, message = reload_nginx()
    if not success:
        os.remove(filepath)
        return jsonify({"error": message}), 500
        
    return jsonify({"success": True, "message": f"Rule for port {inbound_port} added."}), 201

@app.route('/api/delete', methods=['POST'])
def delete_rule():
    data = request.json
    filename = data.get('id')

    if not filename or not filename.endswith(".conf") or '/' in filename:
        return jsonify({"error": "Invalid filename provided."}), 400
        
    filepath = os.path.join(TCP_CONFIG_DIR, filename)

    if not os.path.exists(filepath):
        return jsonify({"error": "Rule not found."}), 404
        
    os.remove(filepath)
    
    success, message = reload_nginx()
    if not success:
        return jsonify({"error": f"File deleted, but failed to reload Nginx: {message}"}), 500

    return jsonify({"success": True, "message": f"Rule {filename} deleted."})

if __name__ == '__main__':
    # The API service runs as root, so no sudo is needed for internal commands.
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
<html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Nginx 端口转发管理</title><style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;background-color:#f8f9fa;color:#212529;margin:0;padding:2rem}.container{max-width:900px;margin:auto;background:#fff;padding:2rem;border-radius:8px;box-shadow:0 4px 6px rgba(0,0,0,.1)}h1,h2{color:#007bff;border-bottom:2px solid #dee2e6;padding-bottom:.5rem}form{margin-bottom:2rem;padding:1.5rem;background-color:#e9ecef;border-radius:6px;display:flex;flex-wrap:wrap;align-items:flex-end;gap:1rem}.form-group{flex:1;min-width:200px}label{display:block;margin-bottom:.5rem;font-weight:700}input[type=text],input[type=number]{width:100%;box-sizing:border-box;padding:10px;border:1px solid #ced4da;border-radius:4px;font-size:1rem}button{padding:10px 20px;font-size:1rem;color:#fff;background-color:#007bff;border:none;border-radius:4px;cursor:pointer;transition:background-color .2s;white-space:nowrap}button:hover{background-color:#0056b3}button:disabled{background-color:#6c757d;cursor:not-allowed}table{width:100%;border-collapse:collapse;margin-top:1rem}th,td{padding:12px;border-bottom:1px solid #dee2e6;text-align:left}th{background-color:#f2f2f2}.delete-btn{background-color:#dc3545}.delete-btn:hover{background-color:#c82333}.message{padding:1rem;margin-bottom:1rem;border-radius:4px;font-weight:700}.success{background-color:#d4edda;color:#155724}.error{background-color:#f8d7da;color:#721c24}</style></head><body><div class="container"><h1>Nginx 端口转发管理</h1><div id="message-area"></div><h2>添加新规则</h2><form id="add-rule-form"><div class="form-group"><label for="inbound_port">入站端口</label><input type="number" id="inbound_port" placeholder="例如: 8888" required></div><div class="form-group"><label for="dest_addr">目标地址</label><input type="text" id="dest_addr" placeholder="IP或域名" required></div><div class="form-group"><label for="dest_port">目标端口</label><input type="number" id="dest_port" placeholder="例如: 80" required></div><button type="submit">添加规则</button></form><h2>当前规则</h2><table id="rules-table"><thead><tr><th>规则名称</th><th>操作</th></tr></thead><tbody></tbody></table></div><script>const API_BASE="/api",form=document.getElementById("add-rule-form"),tableBody=document.querySelector("#rules-table tbody"),messageArea=document.getElementById("message-area");function showMessage(e,t){messageArea.innerHTML=`<div class="message ${t}">${e}</div>`,setTimeout(()=>{messageArea.innerHTML=""},5e3)}async function fetchRules(){try{const e=await fetch(`${API_BASE}/rules`),t=await e.json();tableBody.innerHTML="",0===t.length?tableBody.innerHTML='<tr><td colspan="2">暂无转发规则。</td></tr>':t.forEach(e=>{tableBody.innerHTML+=`<tr><td>${e.name}</td><td><button class="delete-btn" onclick="deleteRule('${e.id}')">删除</button></td></tr>`})}catch(e){showMessage(`加载规则失败: ${e}`,"error")}}form.addEventListener("submit",async e=>{e.preventDefault();const t={inbound_port:document.getElementById("inbound_port").value,dest_addr:document.getElementById("dest_addr").value,dest_port:document.getElementById("dest_port").value},o=form.querySelector("button");o.disabled=!0,o.textContent="添加中...";try{const e=await fetch(`${API_BASE}/add`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(t)}),n=await e.json();if(!e.ok)throw new Error(n.error||"未知错误");showMessage(n.message||"规则添加成功!","success"),form.reset(),fetchRules()}catch(e){showMessage(`添加失败: ${e.message}`,"error")}finally{o.disabled=!1,o.textContent="添加规则"}}),async function deleteRule(e){if(!confirm(`确定要删除规则 ${e} 吗？`))return;try{const t=await fetch(`${API_BASE}/delete`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({id:e})}),o=await t.json();if(!t.ok)throw new Error(o.error||"未知错误");showMessage(o.message||"规则删除成功!","success"),fetchRules()}catch(e){showMessage(`删除失败: ${e.message}`,"error")}}document.addEventListener("DOMContentLoaded",fetchRules);</script></body></html>
EOF
    log_success "Frontend web interface created."
}

configure_firewall() {
    log_info "Configuring firewall (UFW)..."
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 22/tcp  # Always allow SSH
        ufw allow 80/tcp  # Allow access to the web panel
        
        # Enable UFW if it's not already active. Use --force to avoid interactive prompts.
        if ! ufw status | grep -q "Status: active"; then
            ufw --force enable
        fi
        log_success "Firewall configured to allow SSH (22) and HTTP (80)."
    else
        log_info "UFW not found. Skipping firewall configuration. Please configure your firewall manually."
    fi
}

start_services() {
    log_info "Enabling and starting all services..."
    systemctl daemon-reload
    systemctl enable port-manager.service
    systemctl start port-manager.service
    # Use restart to ensure Nginx picks up all changes from a clean state.
    systemctl restart nginx
    
    # CRITICAL VERIFICATION: Check that both services are active.
    if ! systemctl is-active --quiet port-manager.service; then
        log_error "The port-manager API service failed to start. Check logs with 'journalctl -u port-manager.service'."
        exit 1
    fi
    if ! systemctl is-active --quiet nginx.service; then
        log_error "The Nginx service failed to start. Check logs with 'journalctl -u nginx.service'."
        exit 1
    fi
    log_success "All services are running."
}

# --- Script Execution Logic ---
main() {
    install_dependencies
    configure_nginx
    create_backend_api
    create_systemd_service
    create_frontend
    # Sudoers configuration is implicitly handled by running the service as root.
    start_services
    configure_firewall
    
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
