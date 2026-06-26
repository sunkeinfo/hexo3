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
