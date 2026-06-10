#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 一键安装配置代理脚本
# 用法: sudo bash setup.sh
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
RESOURCE_DIR="$SCRIPT_DIR/resources"
INSTALL_DIR="/opt/mihomo"
BIN_PATH="/usr/local/bin/mihomo"

# ---------- 加载配置 ----------
CONFIG_FILE="$CONFIG_DIR/config.sh"
[ ! -f "$CONFIG_FILE" ] && err "配置文件不存在: $CONFIG_FILE"
source "$CONFIG_FILE"

if [ -z "${SUBSCRIBE_URL:-}" ] || [ "$SUBSCRIBE_URL" = "YOUR_SUBSCRIPTION_URL_HERE" ]; then
    err "请先在 config/config.sh 中填写你的订阅链接 (SUBSCRIBE_URL)"
fi

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  代理一键安装脚本${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# ---------- 1. 停止旧进程 ----------
echo -e "${YELLOW}--- Step 1: 停止旧进程 ---${NC}"
pkill -f "$BIN_PATH" 2>/dev/null && log "已停止旧进程" || log "无运行中的旧进程"
sleep 1

# ---------- 2. 获取 mihomo 二进制 ----------
echo ""
echo -e "${YELLOW}--- Step 2: 获取 mihomo 二进制 ---${NC}"

LOCAL_BIN="$RESOURCE_DIR/mihomo"
MIRRORS=(
    "https://gh-proxy.com/https://github.com/MetaCubeX/mihomo/releases/download/v1.19.3/mihomo-linux-amd64-v1.19.3.gz"
    "https://ghproxy.net/https://github.com/MetaCubeX/mihomo/releases/download/v1.19.3/mihomo-linux-amd64-v1.19.3.gz"
    "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.3/mihomo-linux-amd64-v1.19.3.gz"
)

install_binary() {
    # 1. 优先使用本地资源
    if [ -f "$LOCAL_BIN" ]; then
        log "从本地 resources/mihomo 安装 (离线模式)..."
        cp "$LOCAL_BIN" "$BIN_PATH"
        chmod +x "$BIN_PATH"
        return 0
    fi

    # 2. 已安装则复用
    if [ -x "$BIN_PATH" ] && "$BIN_PATH" -v &>/dev/null; then
        log "mihomo 已安装, 跳过"
        return 0
    fi

    # 3. 从镜像下载
    for url in "${MIRRORS[@]}"; do
        local label="${url%%/https*}"
        label="${label%%/github*}"
        if [[ "$url" == https://gh-proxy.com/* ]]; then
            label="gh-proxy.com 镜像"
        elif [[ "$url" == https://ghproxy.net/* ]]; then
            label="ghproxy.net 镜像"
        else
            label="GitHub 直连"
        fi
        warn "尝试下载 ($label)..."
        if curl -fL --connect-timeout 10 --max-time 180 "$url" -o /tmp/mihomo.gz 2>/dev/null; then
            gunzip -f /tmp/mihomo.gz
            mv /tmp/mihomo "$BIN_PATH"
            chmod +x "$BIN_PATH"
            log "下载成功! (来源: $label)"
            return 0
        fi
        warn "该源失败, 尝试下一个..."
    done

    err "所有下载源均失败, 请手动将 mihomo 二进制放入 resources/ 目录"
}

install_binary
log "mihomo 版本: $($BIN_PATH -v 2>&1 | head -1)"

# ---------- 3. 生成配置 ----------
echo ""
echo -e "${YELLOW}--- Step 3: 生成配置文件 ---${NC}"
mkdir -p "$INSTALL_DIR"

cat > "$INSTALL_DIR/config.yaml" << YAML_END
# Mihomo 配置文件 (由 setup.sh 自动生成)
mixed-port: ${PROXY_PORT}
allow-lan: false
bind-address: "127.0.0.1"
mode: rule
log-level: info
external-controller: "127.0.0.1:${API_PORT}"

profile:
  store-selected: true
  store-fake-ip: true

proxy-providers:
  airport:
    type: http
    url: "${SUBSCRIBE_URL}"
    interval: 3600
    path: ./airport-providers.yaml
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 300

proxy-groups:
  - name: PROXY
    type: select
    use:
      - airport
    proxies:
      - DIRECT

  - name: GLOBAL
    type: select
    proxies:
      - PROXY
      - DIRECT

rules:
  - IP-CIDR,127.0.0.0/8,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT
  - IP-CIDR,192.168.0.0/16,DIRECT
  - MATCH,GLOBAL
YAML_END

log "配置文件写入: $INSTALL_DIR/config.yaml"

# ---------- 4. 启动代理 ----------
echo ""
echo -e "${YELLOW}--- Step 4: 启动代理服务 ---${NC}"

cd "$INSTALL_DIR"
nohup "$BIN_PATH" -d "$INSTALL_DIR" > /var/log/mihomo.log 2>&1 &
PID=$!
sleep 3

kill -0 "$PID" 2>/dev/null && log "代理已启动, PID: $PID" || err "启动失败, 请查看日志: cat /var/log/mihomo.log"

# ---------- 5. 配置 proxychains4 ----------
echo ""
echo -e "${YELLOW}--- Step 5: 配置 proxychains4 ---${NC}"

if command -v proxychains4 &>/dev/null; then
    log "proxychains4 已安装"
else
    warn "安装 proxychains4..."
    apt-get update -qq 2>/dev/null && apt-get install -y -qq proxychains4 2>/dev/null && log "安装完成" || warn "安装失败, 可手动安装或使用环境变量方式"
fi

if [ -f /etc/proxychains4.conf ]; then
    sed -i '/^\[ProxyList\]/,$d' /etc/proxychains4.conf
    cat >> /etc/proxychains4.conf <<< "[ProxyList]
socks5 127.0.0.1 ${PROXY_PORT}"
    log "proxychains4 配置更新"
fi

# ---------- 6. 安装 proxy 管理命令 ----------
echo ""
echo -e "${YELLOW}--- Step 6: 安装 proxy 管理命令 ---${NC}"

cat "$SCRIPT_DIR/templates/proxy.sh" > /usr/local/bin/proxy
sed -i "s/API_PORT=\"9090\"/API_PORT=\"${API_PORT}\"/" /usr/local/bin/proxy
sed -i "s/PROXY_PORT=\"7890\"/PROXY_PORT=\"${PROXY_PORT}\"/" /usr/local/bin/proxy
chmod +x /usr/local/bin/proxy
log "管理命令已安装: proxy"
# ---------- 7. 智能节点选择 ----------
echo ""
echo -e "${YELLOW}--- Step 7: 选择初始节点 ---${NC}"

# 等待订阅拉取
warn "等待订阅拉取 (最多 30 秒)..."
for i in $(seq 1 30); do
    NODE_COUNT=$(curl -sf "http://127.0.0.1:${API_PORT}/proxies/PROXY" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(len([n for n in d.get('all',[]) if n!='DIRECT']))" 2>/dev/null || echo "0")
    if [ "$NODE_COUNT" -gt 0 ]; then
        log "订阅拉取成功, 共 $NODE_COUNT 个节点"
        break
    fi
    sleep 2
done

if [ "$NODE_COUNT" -eq 0 ]; then
    warn "订阅拉取超时, 请手动运行: proxy update && proxy list"
    NODE="DIRECT"
else
    # --- 智能选择节点 ---
    SELECTED_NODE=$(curl -sf "http://127.0.0.1:${API_PORT}/proxies/PROXY" | python3 -c "
import sys, json, re
from collections import defaultdict

d = json.load(sys.stdin)
all_nodes = [n for n in d.get('all', []) if n != 'DIRECT']

# 按区域分组
regions = defaultdict(list)
for name in all_nodes:
    m = re.match(r'^[\w-]*?([A-Z]{2,3})[\s\-_]', name)
    region = m.group(1) if m else 'OTHER'
    regions[region].append(name)

target = '${DEFAULT_REGION}'

if target == 'auto':
    # 自动选 HK > TW > SG > JP > US > 其他
    priority = ['HK', 'TW', 'SG', 'JP', 'US']
    for p in priority:
        if p in regions:
            print(regions[p][0])
            exit(0)
    # fallback: 第一个节点
    print(all_nodes[0] if all_nodes else 'DIRECT')
elif target in regions:
    # 指定区域存在
    print(regions[target][0])
else:
    # 指定区域不存在, 列出所有可用区域
    print('__NO_MATCH__')
    print('Available regions:', ','.join(sorted(regions.keys())), file=sys.stderr)
" 2>/dev/null)

    if [ "$SELECTED_NODE" = "__NO_MATCH__" ] || [ -z "$SELECTED_NODE" ]; then
        # 区域不匹配, 列出可用区域
        warn "未找到区域 '${DEFAULT_REGION}' 的节点"
        echo ""
        AVAILABLE=$(curl -sf "http://127.0.0.1:${API_PORT}/proxies/PROXY" | python3 -c "
import sys, json, re
from collections import Counter
d = json.load(sys.stdin)
regions = Counter()
for name in d.get('all', []):
    if name == 'DIRECT': continue
    m = re.match(r'^[\w-]*?([A-Z]{2,3})[\s\-_]', name)
    regions[m.group(1) if m else 'OTHER'] += 1
for r, c in regions.most_common():
    print(f'  {r}: {c} 个节点')
" 2>/dev/null)
        echo "可用区域:"
        echo "$AVAILABLE"
        echo ""
        warn "自动选择第一个可用节点..."
        SELECTED_NODE=$(curl -sf "http://127.0.0.1:${API_PORT}/proxies/PROXY" | \
            python3 -c "import sys,json; d=json.load(sys.stdin); nodes=[n for n in d.get('all',[]) if n!='DIRECT']; print(nodes[0] if nodes else 'DIRECT')" 2>/dev/null)
    fi
fi

if [ "$SELECTED_NODE" != "DIRECT" ] && [ -n "$SELECTED_NODE" ]; then
    curl -sf -X PUT "http://127.0.0.1:${API_PORT}/proxies/PROXY" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$SELECTED_NODE\"}" > /dev/null 2>&1
    log "初始节点: $SELECTED_NODE"
else
    warn "无可用节点, 设为直连模式"
    SELECTED_NODE="DIRECT"
fi

# ---------- 8. 验证 ----------
echo ""
echo -e "${YELLOW}--- Step 8: 验证连通性 ---${NC}"

if [ "$SELECTED_NODE" != "DIRECT" ]; then
    HTTP_CODE=$(curl -sf --proxy "http://127.0.0.1:${PROXY_PORT}" --connect-timeout 10 \
        https://www.google.com -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        log "代理连通性测试通过 (Google: 200)"
    else
        warn "Google 连通性测试失败 (HTTP: $HTTP_CODE), 尝试切换其他节点: proxy switch <节点名>"
    fi
else
    warn "当前为直连模式, 跳过连通性测试"
fi

# ---------- 完成 ----------
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  安装完成!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "  代理地址:    ${GREEN}http://127.0.0.1:${PROXY_PORT}${NC}  (HTTP + SOCKS5)"
echo -e "  管理命令:    ${GREEN}proxy${NC}"
echo ""
echo -e "  速查:"
echo -e "    proxy list             按区域查看所有节点"
echo -e "    proxy info             查看状态 & 连通性"
echo -e "    proxy mode proxy       代理模式 (走代理)"
echo -e "    proxy mode direct      直连模式 (不走代理)"
echo -e "    proxy switch <节点>    切换节点 (支持简写)"
echo -e "    proxy update           更新订阅"
echo -e "    proxy help             完整帮助"
echo ""
echo -e "  终端代理:"
echo -e "    export http_proxy=http://127.0.0.1:${PROXY_PORT}"
echo -e "    export https_proxy=http://127.0.0.1:${PROXY_PORT}"
echo ""
echo -e "    proxychains4 <命令>"
echo ""
