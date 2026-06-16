# vps-init — VPS 综合管理脚本

适用于 **Debian / Ubuntu** 的一站式 VPS 初始化、安全加固与代理管理脚本。

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wujiyu2933121230-ai/test/main/install.sh)
```

安装后可直接使用 `sudo vps` 运行。

## 手动安装

```bash
git clone https://github.com/wujiyu2933121230-ai/test.git
cd test/vps-init
sudo bash vps-init.sh
```

## 功能模块

| 模块 | 功能 |
|------|------|
| **1. VPS 初始化** | 系统更新、基础工具、Swap、fail2ban、BBR、时区、DNS、IPv4 优先 |
| **2. SSH 安全配置** | 改端口、密码/密钥管理、创建用户 |
| **3. 防火墙管理** | UFW 安装、端口放行/关闭 |
| **4. anytls-go 代理** | 安装、配置、密码管理、端口修改 |
| **5. Hysteria2 代理** | 安装、一键配置、端口跳跃、订阅链接 |
| **6. 卸载 vps-init** | 清理所有安装文件与快捷命令 |

## 系统要求

- Debian 10+ / Ubuntu 20.04+
- root 权限

## 卸载

运行 `sudo vps`，在主菜单中选择「卸载 vps-init」即可。

## 许可

MIT
