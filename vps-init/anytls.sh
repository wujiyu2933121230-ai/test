# ═══════════════════════════════════════════════════════════════════════════
# 模块 4: anytls-go 代理管理
# ═══════════════════════════════════════════════════════════════════════════

readonly ANYTLS_VERSION="0.0.12"
readonly ANYTLS_PORT="${ANYTLS_PORT:-8443}"
readonly ANYTLS_DIR="/opt/anytls"
readonly ANYTLS_BIN="${ANYTLS_DIR}/anytls-server"
readonly ANYTLS_PASS_FILE="${ANYTLS_DIR}/password"
readonly ANYTLS_SERVICE="/etc/systemd/system/anytls.service"
readonly ANYTLS_SNI_LIST=("cloudflare.com" "microsoft.com")

anytls_get_current_port() {
    local port
    port=$(grep -oP '(?<=-l )0\.0\.0\.0:\K\d+' "$ANYTLS_SERVICE" 2>/dev/null)
    echo "${port:-$ANYTLS_PORT}"
}

anytls_install() {
    clear
    echo ""
    echo -e "${CYAN}=== 安装 anytls-go v${ANYTLS_VERSION} ===${NC}"
    echo ""

    echo "[1/5] 安装依赖..."
    apt-get update -qq
    apt-get install -y -qq openssl

    echo "[2/5] 复制 anytls-server..."
    mkdir -p "$ANYTLS_DIR"
    cp "${SCRIPT_DIR}/anytls-server" "$ANYTLS_BIN"
    chmod +x "$ANYTLS_BIN"

    if [[ -f "$ANYTLS_PASS_FILE" ]]; then
        log_warn "[3/5] 密码已存在，跳过生成"
    else
        echo "[3/5] 生成随机密码..."
        openssl rand -base64 16 > "$ANYTLS_PASS_FILE"
        chmod 600 "$ANYTLS_PASS_FILE"
        log_ok "密码已保存到 $ANYTLS_PASS_FILE"
    fi
    local pass
    pass=$(cat "$ANYTLS_PASS_FILE")

    echo "[4/5] 创建 systemd 服务..."
    cat > "$ANYTLS_SERVICE" << EOF
[Unit]
Description=anytls-go Server
After=network.target

[Service]
Type=simple
ExecStart=${ANYTLS_BIN} -l 0.0.0.0:${ANYTLS_PORT} -p ${pass}
Restart=always
RestartSec=5
User=root
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable anytls
    systemctl restart anytls

    echo ""
    log_ok "安装完成"
    echo "Server  : 0.0.0.0:${ANYTLS_PORT}"
    echo "Password: ${pass}"
    press_enter
}

anytls_config() {
    clear
    if [[ ! -f "$ANYTLS_PASS_FILE" ]]; then
        log_error "未安装 anytls-go，请先安装"
        press_enter
        return
    fi

    local pass ip sni port
    pass=$(cat "$ANYTLS_PASS_FILE")
    ip=$(public_ip)
    sni="${ANYTLS_SNI_LIST[$((RANDOM % ${#ANYTLS_SNI_LIST[@]}))]}"
    port=$(anytls_get_current_port)

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           anytls-go 服务端配置               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Server IP  : ${ip}"
    echo "  Port       : ${port}"
    echo "  Password   : ${pass}"
    echo ""

    echo -e "${CYAN}── mihomo 客户端配置 ──${NC}"
    echo ""
    cat << EOF
proxies:
- name: anytls
  type: anytls
  server: ${ip}
  port: ${port}
  password: "${pass}"
  client-fingerprint: chrome
  udp: true
  sni: "${sni}"
  alpn:
    - h2
    - http/1.1
  skip-cert-verify: true
EOF
    echo ""
    echo -e "${CYAN}── v2rayN 分享链接 ──${NC}"
    echo ""
    local enc_pass
    enc_pass=$(url_encode "$pass")
    echo "anytls://${enc_pass}@${ip}:${port}?security=tls&sni=${sni}&fp=chrome&alpn=h2%2Chttp%2F1.1&insecure=1&allowInsecure=1&type=tcp&headerType=none#anytls"
    echo ""
    press_enter
}

anytls_restart() {
    echo ""
    systemctl restart anytls 2>/dev/null || { log_error "服务未安装"; press_enter; return; }
    if systemctl is-active --quiet anytls 2>/dev/null; then
        log_ok "服务已重启"
    else
        log_error "重启失败"
    fi
    press_enter
}

anytls_logs() {
    echo ""
    echo -e "${GREEN}=== 实时日志 (Ctrl+C 退出) ===${NC}"
    journalctl -u anytls -f 2>/dev/null || log_error "服务未安装"
}

anytls_chpass() {
    clear
    if [[ ! -f "$ANYTLS_PASS_FILE" ]]; then
        log_error "未安装 anytls-go，请先安装"
        press_enter
        return
    fi

    echo ""
    local newpass
    newpass=$(openssl rand -base64 16)
    printf '%s' "$newpass" > "$ANYTLS_PASS_FILE"
    chmod 600 "$ANYTLS_PASS_FILE"

    sed -i "s|^ExecStart=.*|ExecStart=${ANYTLS_BIN} -l 0.0.0.0:${ANYTLS_PORT} -p ${newpass}|" "$ANYTLS_SERVICE"
    systemctl daemon-reload
    systemctl restart anytls

    log_ok "密码已重新生成并重启服务"
    echo "新密码: ${newpass}"
    press_enter
}

anytls_status() {
    echo ""
    if [[ -f "$ANYTLS_PASS_FILE" ]]; then
        echo "密码: $(cat "$ANYTLS_PASS_FILE")"
    else
        log_warn "密码文件不存在"
    fi
    echo ""
    systemctl status anytls 2>/dev/null || log_error "服务未安装"
    press_enter
}

anytls_chport() {
    clear
    if [[ ! -f "$ANYTLS_SERVICE" ]]; then
        log_error "未安装 anytls-go，请先安装"
        press_enter
        return
    fi

    echo ""
    echo -e "${CYAN}=== 修改端口 ===${NC}"
    echo ""

    local current_port
    current_port=$(anytls_get_current_port)
    echo "当前端口: $current_port"
    echo ""

    local new_port
    read -rp "输入新端口号 (留空取消): " new_port
    [[ -z "$new_port" ]] && { log_info "已取消"; press_enter; return; }

    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        log_error "无效端口号"
        press_enter
        return
    fi

    if [[ "$new_port" == "$current_port" ]]; then
        log_info "端口已是 $new_port，无需修改"
        press_enter
        return
    fi

    sed -i "s|-l 0.0.0.0:[0-9]*|-l 0.0.0.0:${new_port}|" "$ANYTLS_SERVICE"
    systemctl daemon-reload
    systemctl restart anytls

    log_ok "端口已修改为 $new_port"
    press_enter
}

anytls_uninstall() {
    clear
    echo ""
    echo -e "${RED}=== 卸载 anytls-go ===${NC}"
    echo ""

    if ! confirm "确定要卸载 anytls-go？"; then
        log_info "已取消"
        press_enter
        return
    fi

    systemctl stop anytls 2>/dev/null || true
    systemctl disable anytls 2>/dev/null || true
    rm -f "$ANYTLS_SERVICE"
    systemctl daemon-reload
    rm -rf "$ANYTLS_DIR"
    log_ok "卸载完成"
    press_enter
}

anytls_menu() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║        anytls-go 代理管理            ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"

        if [[ -x "$ANYTLS_BIN" ]] && systemctl is-active --quiet anytls 2>/dev/null; then
            echo -e "${CYAN}║  状态: ${GREEN}已安装运行中${NC}                  ${CYAN}║${NC}"
        elif [[ -x "$ANYTLS_BIN" ]] || [[ -f "$ANYTLS_PASS_FILE" ]]; then
            echo -e "${CYAN}║  状态: ${YELLOW}已安装 (未运行)${NC}               ${CYAN}║${NC}"
        else
            echo -e "${CYAN}║  状态: ${RED}未安装${NC}                        ${CYAN}║${NC}"
        fi

        echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║  1. 安装                             ║${NC}"
        echo -e "${CYAN}║  2. 查看配置                         ║${NC}"
        echo -e "${CYAN}║  3. 重启服务                         ║${NC}"
        echo -e "${CYAN}║  4. 查看日志                         ║${NC}"
        echo -e "${CYAN}║  5. 重新生成密码                     ║${NC}"
        echo -e "${CYAN}║  6. 查看服务状态                     ║${NC}"
        echo -e "${CYAN}║  7. 修改端口                         ║${NC}"
        echo -e "${CYAN}║  8. 卸载                             ║${NC}"
        echo -e "${CYAN}║  0. 返回主菜单                       ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
        echo ""
        read -rp "请选择 [0-8]: " choice

        case "$choice" in
            1) anytls_install ;;
            2) anytls_config ;;
            3) anytls_restart ;;
            4) anytls_logs ;;
            5) anytls_chpass ;;
            6) anytls_status ;;
            7) anytls_chport ;;
            8) anytls_uninstall ;;
            0) break ;;
            *) log_error "无效选项"; sleep 1 ;;
        esac
    done
}
