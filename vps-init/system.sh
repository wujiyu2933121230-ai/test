# ═══════════════════════════════════════════════════════════════════════════
# 模块 1: VPS 初始化
# ═══════════════════════════════════════════════════════════════════════════

step_system_update() {
    log_step "1/9 系统更新"
    apt update
    DEBIAN_FRONTEND=noninteractive apt upgrade -y
    log_ok "系统更新完成"
}

step_install_tools() {
    log_step "2/9 安装基础工具"
    local pkgs=(curl wget net-tools dnsutils mtr traceroute htop lsof vim rsync zip unzip tmux git ufw)
    local missing=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "安装: ${missing[*]}"
        DEBIAN_FRONTEND=noninteractive apt install -y "${missing[@]}"
    else
        log_info "所有工具已安装"
    fi
}

step_system_cleanup() {
    log_step "3/9 系统清理"
    apt autoremove --purge -y
    apt autoclean -y
    journalctl --vacuum-size=50M 2>/dev/null || true
    log_ok "系统清理完成"
}

step_configure_swap() {
    log_step "4/9 配置 Swap (1G)"

    if swapon --show 2>/dev/null | grep -q .; then
        log_info "Swap 已存在，跳过创建"
        return
    fi

    local swapfile="/swapfile"
    if [[ -f "$swapfile" ]]; then
        log_info "Swap 文件已存在，跳过"
        return
    fi

    log_info "创建 1G swap 文件..."
    dd if=/dev/zero of="$swapfile" bs=1M count=1024 status=progress
    chmod 600 "$swapfile"
    mkswap "$swapfile"
    swapon "$swapfile"

    if ! grep -q "$swapfile" /etc/fstab; then
        echo "$swapfile none swap sw 0 0" >> /etc/fstab
    fi

    log_ok "Swap 创建完成"
    free -h | grep -i swap
}

step_fail2ban() {
    log_step "5/9 安装配置 fail2ban"

    if ! dpkg -s fail2ban &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt install -y fail2ban
    fi

    local ssh_port
    ssh_port=$(get_current_ssh_port)
    ssh_port=${ssh_port:-22}

    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = $ssh_port
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

    systemctl enable fail2ban --now
    systemctl restart fail2ban
    log_ok "fail2ban 已配置 (SSH 端口: $ssh_port)"
}

step_enable_bbr() {
    log_step "6/9 开启 BBR"

    local sysctl_file="/etc/sysctl.d/99-bbr.conf"

    cat > "$sysctl_file" << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl --system > /dev/null 2>&1

    local cc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    log_ok "BBR 已开启，当前拥塞控制算法: $cc"
}

step_timezone() {
    log_step "7/9 设置时区"
    timedatectl set-timezone Asia/Shanghai
    log_ok "时区已设置为 $(timedatectl show --property=Timezone --value)"
}

step_optimize_dns() {
    log_step "8/9 优化 DNS"

    if command -v resolvectl &>/dev/null; then
        local iface
        iface=$(get_network_interface)
        resolvectl dns "$iface" 8.8.8.8 1.1.1.1
        resolvectl domain "$iface" "~."
        log_ok "DNS 已通过 resolvectl 设置"
    elif [[ -L /etc/resolv.conf ]]; then
        log_warn "/etc/resolv.conf 是符号链接，跳过直接写入"
        log_warn "请手动配置 DNS: resolvectl dns <iface> 8.8.8.8 1.1.1.1"
    else
        cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
        log_ok "DNS 已设置为 8.8.8.8, 1.1.1.1"
    fi
}

step_ipv4_priority() {
    log_step "9/9 IPv4 优先"

    local gai_file="/etc/gai.conf"
    touch "$gai_file"

    if grep -q "^#precedence ::ffff:0:0/96  100" "$gai_file" 2>/dev/null; then
        sed -i 's/^#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' "$gai_file"
    elif ! grep -q "^precedence ::ffff:0:0/96  100" "$gai_file" 2>/dev/null; then
        echo "precedence ::ffff:0:0/96  100" >> "$gai_file"
    fi

    log_ok "IPv4 优先级已设置"
}

vps_init_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        VPS 初始化                    ║${NC}"
    echo -e "${CYAN}║        适用于 Debian / Ubuntu        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "将依次执行以下 9 个步骤:"
    echo "  1. 系统更新"
    echo "  2. 安装基础工具"
    echo "  3. 系统清理"
    echo "  4. 配置 Swap (1G)"
    echo "  5. 安装配置 fail2ban"
    echo "  6. 开启 BBR"
    echo "  7. 设置时区 (Asia/Shanghai)"
    echo "  8. 优化 DNS (8.8.8.8 / 1.1.1.1)"
    echo "  9. IPv4 优先"
    echo ""

    if ! confirm "确认开始初始化？"; then
        log_info "已取消"
        press_enter
        return
    fi

    step_system_update
    step_install_tools
    step_system_cleanup
    step_configure_swap
    step_fail2ban
    step_enable_bbr
    step_timezone
    step_optimize_dns
    step_ipv4_priority

    local port_display
    port_display=$(get_current_ssh_port)
    port_display=${port_display:-22}

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         初始化完成！                  ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  SSH 端口:   $port_display                       ║${NC}"
    echo -e "${CYAN}║  时区:      Asia/Shanghai            ║${NC}"
    echo -e "${CYAN}║  BBR:       已开启                    ║${NC}"
    echo -e "${CYAN}║  DNS:       8.8.8.8, 1.1.1.1        ║${NC}"
    echo -e "${CYAN}║  Swap:      1G                       ║${NC}"
    echo -e "${CYAN}║  fail2ban:  已配置                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""
    log_warn "建议重启 VPS 使所有配置生效: reboot"
    press_enter
}
