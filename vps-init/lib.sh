# ── 颜色 ──
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ── 日志函数 ──
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_step()  { echo -e "\n${BLUE}=== $* ===${NC}"; }

# ── 交互辅助 ──
press_enter() {
    echo ""
    read -rp "按回车键继续..." _
}

confirm() {
    local prompt="$1"
    local ans
    read -rp "$(echo -e "${CYAN}${prompt} [y/N]: ${NC}")" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# ── 权限检查 ──
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 身份运行此脚本"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/debian_version ]]; then
        log_error "此脚本仅支持 Debian/Ubuntu 系统"
        exit 1
    fi
}

# ── 共享工具 ──
public_ip() {
    local ip
    for s in ip.sb ifconfig.me api.ipify.org ipv4.icanhazip.com checkip.amazonaws.com; do
        ip=$(curl -4 -sS --connect-timeout 3 --max-time 5 "https://$s" 2>/dev/null) || true
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return
        fi
    done
    echo "unknown"
}

gen_password() {
    openssl rand -base64 16 | tr -d "=+/" | cut -c1-16
}

url_encode() {
    python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))" 2>/dev/null || \
    printf '%s' "$1" | od -An -tx1 | tr -d ' \n' | sed 's/../%&/g'
}

get_current_ssh_port() {
    if systemctl is-active --quiet ssh.socket 2>/dev/null; then
        grep -Po '^ListenStream=\K\d+' /etc/systemd/system/ssh.socket.d/port.conf 2>/dev/null \
            || grep -Po '^ListenStream=\K\d+' /lib/systemd/system/ssh.socket 2>/dev/null \
            || grep -Po '^ListenStream=\K\d+' /etc/systemd/system/ssh.socket 2>/dev/null \
            || echo 22
    else
        grep -Po '^Port\s+\K\d+' /etc/ssh/sshd_config 2>/dev/null || echo 22
    fi
}

get_network_interface() {
    local iface
    iface=$(ip route | grep default | head -1 | awk '{print $5}')
    if [[ -z "$iface" ]]; then
        iface=$(ip link show | grep -E "^[0-9]+:" | grep -v lo | head -1 | awk -F': ' '{print $2}')
    fi
    echo "${iface:-eth0}"
}
