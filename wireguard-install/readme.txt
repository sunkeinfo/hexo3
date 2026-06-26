hello
脚本已修改完成，实现了全自动化安装。以下是所有改动的说明：

__`installQuestions()` 函数__ — 移除了所有 `read` 交互提问，改为自动检测/赋值：

- __公网 IP__：自动通过 `ip -4 addr` / `ip -6 addr` 检测
- __公网网卡__：自动通过 `ip -4 route` 检测默认路由网卡
- __WireGuard 接口名__：固定为 `wg0`
- __服务端 VPN IPv4__：固定为 `10.66.66.1`
- __服务端 VPN IPv6__：固定为 `fd42:42:42::1`
- __监听端口__：随机生成（49152-65535 范围）
- __DNS__：固定使用 Cloudflare `1.1.1.1` / `1.0.0.1`
- __AllowedIPs__：固定为 `0.0.0.0/0,::/0`（全流量走 VPN）
- 移除了末尾的 `Press any key to continue...` 等待

__`newClient()` 函数__ — 支持传入客户端名称参数，自动跳过所有交互：

- 客户端名称直接使用传入的参数（首次安装时传入 `"test"`）
- 客户端 IPv4/IPv6 自动从 `.2` 开始顺序分配，无需手动输入
- 若客户端已存在则跳过，不报错退出

__`installWireGuard()` 函数__ — 将 `newClient` 调用改为 `newClient "test"`，安装完成后自动生成名为 `test` 的客户端配置文件，保存在 `/root/wg0-client-test.conf`。


在 installWireGuard() 末尾新增了两个步骤：

下载并替换 wg0.conf：

使用 curl -fsSL 从 https://hosting.sunke.info/wireguard-install/ens5-wireguard-t3micro/wg0.conf 下载文件
直接覆盖写入 /etc/wireguard/wg0.conf（即 /etc/wireguard/${SERVER_WG_NIC}.conf）
下载成功后自动设置权限为 600
若下载失败则打印错误提示，保留原有配置继续运行
重启 WireGuard 服务：

Alpine 系统：rc-service wg-quick.wg0 restart
其他系统（Ubuntu/Debian/Fedora 等）：systemctl restart wg-quick@wg0
重启后继续执行原有的运行状态检查
整个安装流程现在完全无需人工干预：自动检测配置 → 安装 WireGuard → 生成 test 客户端 → 下载远程 wg0.conf 替换 → 重启服务。
