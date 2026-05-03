#!/bin/bash

# =====================================================================
#  Zero-Trust Init for Modern Debian (12+)
#
#  Repository: https://github.com/PhoenixSama/zero-trust-init
#  Author: PhoenixSama
#  Co-authored & Security Audited by: Gemini 3.1 Pro & DeepSeek V3.2
#
#  "Built during a sleepless night, fueled by geek romance and dual-AI synergy."
# =====================================================================

export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${COLOR_RED}致命错误：必须以 root 身份运行此脚本！${COLOR_RESET}"
    exit 1
fi

STATE_DIR="/var/lib/vps_init_state"
mkdir -p "$STATE_DIR"

LOG_FILE="/var/log/vps_init_$(date +%Y%m%d_%H%M%S).log"
exec 3>&1 4>&2
exec 1> >(tee -a "$LOG_FILE") 2>&1
trap 'exec 1>&3 2>&4' EXIT

# --- 动态系统信息 ---
OS_PRETTY_NAME=$(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')
DEBIAN_CODENAME=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d= -f2 | tr -d '\"')

if [ -z "$DEBIAN_CODENAME" ]; then
    echo -e "${COLOR_RED}错误: 无法获取 Debian 代号。此脚本仅支持现代 Debian 发行版。${COLOR_RESET}"
    exit 1
fi

# --- 全局状态追踪变量 ---
TRACK_PORT="默认 22 (未更改)"
TRACK_UFW="未触发配置"
TRACK_ALGO="未触发嗅探"
TRACK_NTP="未触发配置"

# --- 系统预检 (Preflight Check) ---
preflight_check() {
    clear
    echo -e "${COLOR_CYAN}================ ⚡ 系统预检 (Preflight) ⚡ =================${COLOR_RESET}"
    echo -e " 🖥️  操作系统 : $OS_PRETTY_NAME (代号: $DEBIAN_CODENAME)"
    echo -e " ⚙️  内核版本 : $(uname -r)"
    echo -e " 🧠  硬件架构 : $(uname -m)"
    echo -e " 💾  物理内存 : $(free -h | awk '/^Mem:/ {print $2}')"
    echo -e " 💽  可用磁盘 : $(df -h / | awk 'NR==2 {print $4}')"
    echo -e " 📝  执行日志 : $LOG_FILE"
    echo -e "${COLOR_CYAN}=============================================================${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}提示: 此脚本针对现代 Debian 系统自适应，包含高危内核调优与边界防护。${COLOR_RESET}"
    read -p "确认系统环境无误并继续执行？(y/n): " confirm
    [[ $confirm != [Yy]* ]] && echo "已取消执行。" && exit 0
}

preflight_check

echo -e "\n${COLOR_CYAN}正在执行前置依赖检查...${COLOR_RESET}"
MISSING_DEPS=()
for cmd in curl nproc shuf bc jq ss; do
    if ! command -v "$cmd" >/dev/null 2>&1; then MISSING_DEPS+=("$cmd"); fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${COLOR_YELLOW}正在补全基础依赖 (${MISSING_DEPS[*]})...${COLOR_RESET}"
    apt-get update -yq || echo -e "${COLOR_RED}警告: 源更新失败，依赖安装可能受阻！${COLOR_RESET}"
    PKG_LIST=""
    for dep in "${MISSING_DEPS[@]}"; do
        case "$dep" in 
            nproc|shuf) PKG_LIST+=" coreutils" ;; 
            ss) PKG_LIST+=" iproute2" ;;
            *) PKG_LIST+=" $dep" ;; 
        esac
    done
    apt-get install -y $PKG_LIST
fi

GEO_COUNTRY=$(curl -s --max-time 2 https://ipapi.co/country || curl -s --max-time 2 https://ipinfo.io/country || echo "US")
PUBLIC_IP=$(curl -s --max-time 2 https://api.ipify.org || hostname -I | awk '{print $1}')

check_status() {
    if [ -f "${STATE_DIR}/$1" ]; then echo -e "${COLOR_GREEN}[已完成]${COLOR_RESET}"
    else echo -e "${COLOR_YELLOW}[未执行]${COLOR_RESET}"; fi
}
mark_done() { touch "${STATE_DIR}/$1"; }

# --- 模块 1: 更新APT源 ---
task_apt_update() {
    echo -e "${COLOR_YELLOW}配置最优镜像源 ($GEO_COUNTRY) 并适配代号 [$DEBIAN_CODENAME]...${COLOR_RESET}"
    apt-get install -y apt-transport-https ca-certificates
    MIRROR_DEBIAN="https://deb.debian.org/debian/"
    MIRROR_SECURITY="https://deb.debian.org/debian-security/"
    case "$GEO_COUNTRY" in
        CN) MIRROR_DEBIAN="https://mirrors.ustc.edu.cn/debian/"; MIRROR_SECURITY="https://mirrors.ustc.edu.cn/debian-security/" ;;
        HK) MIRROR_DEBIAN="https://mirrors.xtom.hk/debian/"; MIRROR_SECURITY="https://mirrors.xtom.hk/debian-security/" ;;
        JP) MIRROR_DEBIAN="https://mirrors.xtom.jp/debian/"; MIRROR_SECURITY="https://mirrors.xtom.jp/debian-security/" ;;
        TW) MIRROR_DEBIAN="https://free.nchc.org.tw/debian/"; MIRROR_SECURITY="https://mirrors.xtom.hk/debian-security/" ;;
    esac
    cp /etc/apt/sources.list /etc/apt/sources.list.bak
    
    cat > /etc/apt/sources.list <<EOF
deb $MIRROR_DEBIAN $DEBIAN_CODENAME main contrib non-free non-free-firmware
deb-src $MIRROR_DEBIAN $DEBIAN_CODENAME main contrib non-free non-free-firmware
deb $MIRROR_DEBIAN ${DEBIAN_CODENAME}-updates main contrib non-free non-free-firmware
deb-src $MIRROR_DEBIAN ${DEBIAN_CODENAME}-updates main contrib non-free non-free-firmware
deb $MIRROR_DEBIAN ${DEBIAN_CODENAME}-backports main contrib non-free non-free-firmware
deb-src $MIRROR_DEBIAN ${DEBIAN_CODENAME}-backports main contrib non-free non-free-firmware
deb $MIRROR_SECURITY ${DEBIAN_CODENAME}-security main contrib non-free non-free-firmware
deb-src $MIRROR_SECURITY ${DEBIAN_CODENAME}-security main contrib non-free non-free-firmware
EOF
    apt-get update -yq
    mark_done "apt_updated"
    echo -e "${COLOR_GREEN}APT 源配置完成！${COLOR_RESET}"
}

# --- 模块 2: 升级最新内核 ---
task_upgrade_kernel() {
    echo -e "${COLOR_YELLOW}安装最新内核及补丁...${COLOR_RESET}"
    apt-get install -y --only-upgrade sudo 2>/dev/null
    apt-get -t ${DEBIAN_CODENAME}-backports install -y linux-image-amd64 linux-headers-amd64
    update-grub 2>/dev/null
    mark_done "kernel_upgraded"
    echo -e "${COLOR_GREEN}内核及基础提权防护更新完成！${COLOR_RESET}"
}

# --- 模块 3: 多维度 ZRAM ---
task_zram_setup() {
    echo -e "${COLOR_YELLOW}配置 ZRAM 模块并嗅探 CPU...${COLOR_RESET}"
    apt-get install -y zram-tools
    
    detect_zram_algo() {
        local cores=$(nproc)
        local cache_size=$(grep -i "cache size" /proc/cpuinfo | head -n 1 | grep -oE '[0-9]+' || echo 0)
        local has_modern_flags=$(grep -E -i 'avx|avx2|asimd' /proc/cpuinfo | wc -l)
        
        if [ "$cores" -ge 2 ] && { [ "${cache_size:-0}" -ge 8000 ] || [ "$has_modern_flags" -gt 0 ]; }; then
            echo "zstd"
        else
            echo "lz4"
        fi
    }
    
    TRACK_ALGO=$(detect_zram_algo)
    cat > /etc/default/zramswap <<EOF
ALGO=$TRACK_ALGO
PERCENT=50
PRIORITY=100
EOF
    systemctl restart zramswap
    cat > /etc/sysctl.d/99-zram.conf <<EOF
vm.swappiness=100
vm.vfs_cache_pressure=500
vm.watermark_boost_factor=0
vm.watermark_scale_factor=125
vm.page-cluster=0
EOF
    sysctl --system
    mark_done "zram_setup"
    echo -e "${COLOR_GREEN}ZRAM (算法: $TRACK_ALGO) 优化完成！${COLOR_RESET}"
}

# --- 模块 4: 禁用气球驱动 ---
task_disable_balloon() {
    echo "blacklist virtio_balloon" | tee /etc/modprobe.d/blacklist-virtio-balloon.conf
    update-initramfs -u
    mark_done "balloon_disabled"
    echo -e "${COLOR_GREEN}气球驱动已禁用！${COLOR_RESET}"
}

# --- 模块 5: SSH 深度加固与边界防御 (含私钥自选加密) ---
task_ssh_security() {
    echo -e "${COLOR_YELLOW}正在重构 SSH 认证并部署边界防御机制...${COLOR_RESET}"
    
    while true; do
        RANDOM_PORT=$(shuf -i 10000-60000 -n 1)
        if ! ss -tuln | grep -q ":$RANDOM_PORT\b"; then break; fi
    done
    TRACK_PORT="$RANDOM_PORT"
    
    SECURE_DIR="/etc/ssh_secure_keys/root"
    mkdir -p "$SECURE_DIR" && chmod 700 "$SECURE_DIR"

    # ================= 修复核心：交互式设置私钥密码 =================
    echo -e "\n${COLOR_CYAN}>>> SSH 私钥安全设置 <<<${COLOR_RESET}"
    KEY_PASSPHRASE=""
    DISPLAY_PASS="${COLOR_YELLOW}无 (未加密)${COLOR_RESET}"

    while true; do
        read -p "是否为生成的 SSH 私钥设置加密密码？(推荐 y 更安全 / 留空或 n 不设置): " set_pass
        case ${set_pass:-n} in
            [Yy]* )
                while true; do
                    read -sp "请输入你要设置的私钥密码: " KEY_PASSPHRASE
                    echo ""
                    if [ -z "$KEY_PASSPHRASE" ]; then
                        echo -e "${COLOR_RED}密码不能为空！${COLOR_RESET}"
                        continue
                    fi
                    read -sp "请再次输入以确认: " KEY_PASSPHRASE_CONFIRM
                    echo ""
                    if [ "$KEY_PASSPHRASE" == "$KEY_PASSPHRASE_CONFIRM" ]; then
                        DISPLAY_PASS="${COLOR_CYAN}[已设置自定义专属密码]${COLOR_RESET}"
                        break 2
                    else
                        echo -e "${COLOR_RED}两次输入的密码不一致，请重新输入。${COLOR_RESET}"
                    fi
                done
                ;;
            [Nn]* )
                break
                ;;
            * ) echo "请输入 y 或 n";;
        esac
    done
    # =====================================================================

    KEY_TEMP=$(mktemp /tmp/ssh_key_XXXXXX)
    ssh-keygen -t ed25519 -N "$KEY_PASSPHRASE" -f "$KEY_TEMP" -C "root@secure-vps" -q
    cat "${KEY_TEMP}.pub" > "$SECURE_DIR/authorized_keys"
    chmod 600 "$SECURE_DIR/authorized_keys"

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    sed -i 's/^#\?Port .*/Port '"$RANDOM_PORT"'/g' /etc/ssh/sshd_config
    if ! grep -q "^Port" /etc/ssh/sshd_config; then sed -i '1s/^/Port '"$RANDOM_PORT"'\n/' /etc/ssh/sshd_config; fi

    sed -i 's/^#\?PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#\?PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
    sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 30/' /etc/ssh/sshd_config
    sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
    sed -i 's/^#\?AllowAgentForwarding.*/AllowAgentForwarding no/' /etc/ssh/sshd_config
    sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config
    
    if ! grep -q "^MaxAuthTries" /etc/ssh/sshd_config; then echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
    else sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config; fi
    
    sed -i '/^Match User root$/d' /etc/ssh/sshd_config
    sed -i '/^    AuthorizedKeysFile/d' /etc/ssh/sshd_config
    sed -i '/^# --- MATCH BLOCKS MUST BE AT THE EOF ---$/d' /etc/ssh/sshd_config
    cat >> /etc/ssh/sshd_config <<EOF

# --- MATCH BLOCKS MUST BE AT THE EOF ---
Match User root
    AuthorizedKeysFile /etc/ssh_secure_keys/root/authorized_keys
EOF

    echo -e "${COLOR_RED}====================================================${COLOR_RESET}"
    echo -e "私钥密码状态: ${DISPLAY_PASS} | 新SSH端口: ${COLOR_CYAN}${RANDOM_PORT}${COLOR_RESET}"
    echo -e "${COLOR_RED}====================================================${COLOR_RESET}"
    cat "$KEY_TEMP"
    echo -e "${COLOR_RED}====================================================${COLOR_RESET}"
    rm -f "$KEY_TEMP" "${KEY_TEMP}.pub"

    echo -e "${COLOR_YELLOW}正在安装并配置 Fail2ban 防爆破服务...${COLOR_RESET}"
    apt-get install -y fail2ban
    cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = $RANDOM_PORT
maxretry = 3
bantime = 3600
findtime = 600
EOF
    systemctl restart fail2ban

    echo -e "\n${COLOR_CYAN}>>> 防火墙配置选项 <<<${COLOR_RESET}"
    echo "1. 推荐开启 UFW。后续原生服务需手动放行，Docker 自动穿透。"
    echo "2. 极其抗拒防火墙可输入 n，仅依赖 Fail2ban 防御。"
    while true; do
        read -p "是否安装并启用 UFW 防火墙？(y/n): " choice_ufw
        case $choice_ufw in
            [Yy]* )
                apt-get install -y ufw
                ufw default deny incoming
                ufw default allow outgoing
                ufw allow "$RANDOM_PORT"/tcp
                echo "y" | ufw enable >/dev/null 2>&1
                TRACK_UFW="已启用 (允许端口 $RANDOM_PORT)"
                break ;;
            [Nn]* )
                TRACK_UFW="未安装 / 手动跳过"
                break ;;
            * ) echo "请输入 y 或 n";;
        esac
    done

    while true; do
        read -p "已保存好私钥，现在重启 SSHD 吗？(y/n): " confirm_restart
        case $confirm_restart in
            [Yy]* )
                systemctl restart sshd
                mark_done "ssh_secured"
                echo -e "${COLOR_GREEN}SSHD 及其防御矩阵已启动！${COLOR_RESET}"
                echo -e "请在${COLOR_CYAN}新终端${COLOR_RESET}使用以下命令测试:${COLOR_RESET}"
                echo -e "${COLOR_CYAN}ssh -p $RANDOM_PORT -i /path/to/key root@$PUBLIC_IP${COLOR_RESET}"
                break ;;
            [Nn]* )
                echo -e "${COLOR_RED}警告：已回滚 SSH 配置。${COLOR_RESET}"
                mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
                TRACK_PORT="默认 22 (已回滚)"
                
                if systemctl is-active --quiet fail2ban; then
                    sed -i "s/port = $RANDOM_PORT/port = 22/" /etc/fail2ban/jail.local
                    systemctl restart fail2ban
                fi

                if systemctl is-active --quiet ufw && ufw status | grep -q "Status: active"; then
                    echo -e "${COLOR_YELLOW}🚨 紧急介入：已自动将 UFW 紧急放行默认 22 端口防锁死！${COLOR_RESET}"
                    ufw allow 22/tcp >/dev/null 2>&1
                    TRACK_UFW="已启用 (因回滚紧急放行端口 22)"
                fi
                break ;;
            * ) echo "请输入 y 或 n";;
        esac
    done
}

# --- 模块 6: Chrony ---
task_chrony_setup() {
    apt-get install -y chrony
    TRACK_NTP="pool.ntp.org"
    case "$GEO_COUNTRY" in CN) TRACK_NTP="ntp.aliyun.com" ;; HK) TRACK_NTP="hk.pool.ntp.org" ;; JP) TRACK_NTP="jp.pool.ntp.org" ;; TW) TRACK_NTP="tw.pool.ntp.org" ;; esac
    cat > /etc/chrony/chrony.conf <<EOF
server $TRACK_NTP iburst
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
EOF
    systemctl restart chrony
    mark_done "chrony_setup"
    echo -e "${COLOR_GREEN}Chrony 配置完成。${COLOR_RESET}"
}

# --- 模块 7: 内核调优 ---
task_sysctl_tune() {
    cat > /etc/sysctl.d/99-custom-tune.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max = 1048576
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
EOF
    sysctl --system
    mark_done "sysctl_tuned"
    echo -e "${COLOR_GREEN}内核和网络解除上限并调优完成！${COLOR_RESET}"
}

# --- 模块 8: 通用零日防御 ---
task_cve_check() {
    echo -e "${COLOR_YELLOW}部署 0-Day 级别的本地提权通用防御隔离层...${COLOR_RESET}"
    
    if ! grep -q "^AllowUsers root" /etc/ssh/sshd_config; then 
        if grep -q "^# --- MATCH BLOCKS MUST BE AT THE EOF ---$" /etc/ssh/sshd_config; then
            sed -i '/^# --- MATCH BLOCKS MUST BE AT THE EOF ---$/i AllowUsers root' /etc/ssh/sshd_config
        else
            sed -i '1s/^/AllowUsers root\n/' /etc/ssh/sshd_config
        fi
    fi
    
    exclude_users=("docker" "git" "www-data" "mysql" "postgres" "redis")
    for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
        if [[ ! " ${exclude_users[@]} " =~ " ${user} " ]]; then
            usermod -L "$user" 2>/dev/null
            echo "锁定普通用户 [$user] 的密码登录以阻断潜在利用链。"
        fi
    done
    
    if ! systemctl is-active --quiet sshd; then systemctl restart sshd; else systemctl reload sshd; fi
    mark_done "cve_checked"
    echo -e "${COLOR_GREEN}基础纵深防御策略部署完成！${COLOR_RESET}"
}

# --- 执行摘要 ---
show_summary() {
    echo -e "\n${COLOR_CYAN}================ 执行摘要 =================${COLOR_RESET}"
    echo -e "🎯 SSH 连接端口 : ${COLOR_YELLOW}${TRACK_PORT}${COLOR_RESET}"
    echo -e "🛡️ 防火墙状态   : ${COLOR_YELLOW}${TRACK_UFW}${COLOR_RESET}"
    echo -e "🗜️ ZRAM 算法    : ${COLOR_YELLOW}${TRACK_ALGO}${COLOR_RESET}"
    echo -e "⏱️ 时间同步(NTP) : ${COLOR_YELLOW}${TRACK_NTP}${COLOR_RESET}"
    echo -e "📝 日志归档路径 : ${COLOR_YELLOW}${LOG_FILE}${COLOR_RESET}"
    echo -e "${COLOR_CYAN}===========================================${COLOR_RESET}\n"
}

show_menu() {
    clear
    echo -e "=================================================="
    echo -e " Modern Debian (12+) 自动化初始化与调优脚本 (V11.1)"
    echo -e "=================================================="
    echo -e "  1. 动态自适应镜像源     $(check_status apt_updated)"
    echo -e "  2. 升级系统及内核       $(check_status kernel_upgraded)"
    echo -e "  3. 自适应 ZRAM 部署     $(check_status zram_setup)"
    echo -e "  4. 禁用气球驱动         $(check_status balloon_disabled)"
    echo -e "  5. SSH/边界安全防御     $(check_status ssh_secured)"
    echo -e "  6. Chrony 时间同步      $(check_status chrony_setup)"
    echo -e "  7. 现代 Sysctl 调优     $(check_status sysctl_tuned)"
    echo -e "  8. 零日本地提权隔离     $(check_status cve_checked)"
    echo -e "=================================================="
    echo -e " ${COLOR_GREEN}66. 一键顺序执行所有优化 (推荐)${COLOR_RESET}"
    echo -e "  0. 退出"
    echo -e "=================================================="
}

while true; do
    show_menu
    read -p "选择操作 [0-66]: " choice
    case $choice in
        1) task_apt_update; read -p "按回车键继续..." ;;
        2) task_upgrade_kernel; read -p "按回车键继续..." ;;
        3) task_zram_setup; read -p "按回车键继续..." ;;
        4) task_disable_balloon; read -p "按回车键继续..." ;;
        5) task_ssh_security; read -p "按回车键继续..." ;;
        6) task_chrony_setup; read -p "按回车键继续..." ;;
        7) task_sysctl_tune; read -p "按回车键继续..." ;;
        8) task_cve_check; read -p "按回车键继续..." ;;
        66)
            task_apt_update; task_ssh_security
            echo -e "\n${COLOR_RED}⚠️ 警告：接下来将执行高危系统调优，请务必先在新终端用新端口测试 SSH 连接！${COLOR_RESET}"
            echo -e "测试命令: ${COLOR_CYAN}ssh -p ${TRACK_PORT:-22} -i /path/to/key root@$PUBLIC_IP${COLOR_RESET}"
            read -p "确认新端口连接成功？(输入 'ok' 确认继续，其他任意键中止): " confirm
            if [[ "$confirm" != "ok" ]]; then
                echo -e "${COLOR_YELLOW}操作已中止。你可以随时再次运行本脚本。${COLOR_RESET}"
                exit 1
            fi
            task_upgrade_kernel; task_zram_setup; task_disable_balloon; task_chrony_setup; task_sysctl_tune; task_cve_check
            show_summary
            echo -e "${COLOR_GREEN}全部操作完毕！建议立即执行 'reboot'。${COLOR_RESET}"; read ;;
        0) exit 0 ;;
        *) sleep 1 ;;
    esac
done
