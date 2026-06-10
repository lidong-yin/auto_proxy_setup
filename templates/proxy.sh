#!/usr/bin/env bash
# proxy - 代理管理命令
# 用法: 见 proxy help

API_PORT="9090"
API="http://127.0.0.1:${API_PORT}"
PROXY_PORT="7890"
BIN_PATH="/usr/local/bin/mihomo"
INSTALL_DIR="/opt/mihomo"

# ---------- helpers ----------
get_proxy_json() { curl -sf "$API/proxies/PROXY" 2>/dev/null; }
get_global_json() { curl -sf "$API/proxies/GLOBAL" 2>/dev/null; }

get_nodes() {
    get_proxy_json | python3 -c "
import sys, json
d = json.load(sys.stdin)
for name in d.get('all', []):
    if name != 'DIRECT':
        print(name)
" 2>/dev/null
}

get_current_node() {
    get_proxy_json | python3 -c "import sys,json; print(json.load(sys.stdin).get('now','?'))" 2>/dev/null
}

get_current_global() {
    get_global_json | python3 -c "import sys,json; print(json.load(sys.stdin).get('now','?'))" 2>/dev/null
}

get_clash_mode() {
    curl -sf "$API/configs" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode','?'))" 2>/dev/null
}

switch_node() {
    curl -s -X PUT "$API/proxies/PROXY" -H "Content-Type: application/json" -d "{\"name\":\"$1\"}" > /dev/null
}

switch_global() {
    curl -s -X PUT "$API/proxies/GLOBAL" -H "Content-Type: application/json" -d "{\"name\":\"$1\"}" > /dev/null
}

set_clash_mode() {
    curl -s -X PATCH "$API/configs" -H "Content-Type: application/json" -d "{\"mode\":\"$1\"}" > /dev/null
}

# ---------- commands ----------
case "${1:-}" in
    start)
        pkill -f "$BIN_PATH" 2>/dev/null
        sleep 1
        cd "$INSTALL_DIR"
        nohup "$BIN_PATH" -d "$INSTALL_DIR" > /var/log/mihomo.log 2>&1 &
        echo "代理已启动, PID: $!"
        ;;

    stop)
        pkill -f "$BIN_PATH" && echo "代理已停止" || echo "代理未运行"
        ;;

    restart)
        pkill -f "$BIN_PATH" 2>/dev/null
        sleep 1
        cd "$INSTALL_DIR"
        nohup "$BIN_PATH" -d "$INSTALL_DIR" > /var/log/mihomo.log 2>&1 &
        echo "代理已重启, PID: $!"
        ;;

    log)
        tail -50 /var/log/mihomo.log
        ;;

    info)
        echo ""
        echo "========================== 代理状态 =========================="
        echo "  网络模式:  $(get_clash_mode)"
        echo "  GLOBAL:    $(get_current_global)"
        echo "  PROXY:     $(get_current_node)"
        echo ""
        echo "  连通性测试:"
        curl -sf --proxy "http://127.0.0.1:${PROXY_PORT}" --connect-timeout 5 \
            https://www.google.com -o /dev/null -w "    Google : HTTP %{http_code}  %{time_total}s\n" 2>/dev/null || echo "    连接失败"
        curl -sf --proxy "http://127.0.0.1:${PROXY_PORT}" --connect-timeout 5 \
            https://www.youtube.com -o /dev/null -w "    YouTube: HTTP %{http_code}  %{time_total}s\n" 2>/dev/null || echo "    YouTube: 连接失败"
        echo ""
        ;;

    list)
        JSON=$(get_proxy_json)
        if [ -z "$JSON" ]; then
            echo "API 不可达, 请检查代理是否启动"
            exit 1
        fi
        echo "$JSON" | python3 -c "
import sys, json, re
from collections import defaultdict

d = json.load(sys.stdin)
all_nodes = [n for n in d.get('all', []) if n != 'DIRECT']
history = d.get('history', {})
if isinstance(history, list):
    history = {}
current = d.get('now', '')

regions = defaultdict(list)
for name in all_nodes:
    m = re.match(r'^[\w-]*?([A-Z]{2,3})[\s\-_]', name)
    region = m.group(1) if m else 'OTHER'
    h = history.get(name, [])
    delay = h[-1].get('delay', 0) if h else 0
    regions[region].append((delay, name))

region_order = ['HK', 'TW', 'SG', 'JP', 'US', 'KR', 'GB', 'DE', 'OTHER']
for r in region_order:
    if r not in regions:
        continue
    print(f'\n  [{r}]')
    for delay, name in sorted(regions[r], key=lambda x: x[0] if x[0] > 0 else 99999):
        marker = ' << 当前' if name == current else ''
        delay_str = f'{delay}ms' if delay > 0 else '  -'
        print(f'    {name:40s} {delay_str:>8s}{marker}')

for r in sorted(regions):
    if r in region_order:
        continue
    print(f'\n  [{r}]')
    for delay, name in sorted(regions[r], key=lambda x: x[0] if x[0] > 0 else 99999):
        marker = ' << 当前' if name == current else ''
        delay_str = f'{delay}ms' if delay > 0 else '  -'
        print(f'    {name:40s} {delay_str:>8s}{marker}')

print(f'\n  测速排名: proxy speed')
print(f'  切换模式: proxy mode direct | proxy | global')
print()
" 2>/dev/null || echo "解析失败"
        ;;

    regions)
        get_nodes | python3 -c "
import sys, re
from collections import Counter
regions = Counter()
for line in sys.stdin:
    name = line.strip()
    m = re.match(r'^[\w-]*?([A-Z]{2,3})[\s\-_]', name)
    regions[m.group(1) if m else 'OTHER'] += 1
print('可用区域 (节点数):')
for r, count in regions.most_common():
    print(f'  {r}: {count} 个节点')
" 2>/dev/null || echo "API 不可达"
        ;;

    switch)
        if [ -z "${2:-}" ]; then
            echo "用法: proxy switch <节点名|DIRECT>"
            echo ""
            echo "当前节点: $(get_current_node)"
            echo ""
            echo "可用节点:"
            get_nodes | head -20 | while read n; do echo "  $n"; done
            echo "  DIRECT  (直连)"
            echo ""
            echo "查看更多: proxy list"
            exit 1
        fi

        switch_node "$2"
        echo "已切换节点: $2"

        if [ "$2" = "DIRECT" ]; then
            switch_global "DIRECT"
        else
            switch_global "PROXY"
        fi

        ( sleep 2
          curl -sf --proxy "http://127.0.0.1:${PROXY_PORT}" --connect-timeout 5 \
              https://www.google.com -o /dev/null -w "Google: HTTP %{http_code} %{time_total}s\n" 2>/dev/null
        ) &
        ;;

    mode)
        CMODE="${2:-}"
        if [ -z "$CMODE" ]; then
            CLASH=$(get_clash_mode)
            GLOBAL=$(get_current_global)
            NODE=$(get_current_node)
            echo ""
            echo "========================== 当前模式 =========================="
            echo "  mihomo mode: $CLASH"
            echo "  GLOBAL:      $GLOBAL"
            echo "  PROXY:       $NODE"
            echo ""
            echo "  可用模式:"
            echo "    direct   直连 — 所有流量不走代理"
            echo "    proxy    规则 — 按规则路由 (局域网直连, 其余走代理)"
            echo "    global   全局 — 所有流量强行走代理"
            echo ""
            echo "  用法: proxy mode <direct|proxy|global>"
            echo ""
            exit 0
        fi

        case "$CMODE" in
            direct|DIRECT)
                switch_global "DIRECT"
                echo "已切换: 直连模式 (direct)"
                ;;

            proxy|rule|PROXY)
                set_clash_mode "rule"
                switch_global "PROXY"
                CUR=$(get_current_node)
                if [ "$CUR" = "DIRECT" ]; then
                    FIRST=$(get_nodes | head -1)
                    [ -n "$FIRST" ] && switch_node "$FIRST"
                fi
                echo "已切换: 规则模式 (rule), 节点: $(get_current_node)"
                ;;

            global|GLOBAL)
                set_clash_mode "global"
                switch_global "PROXY"
                CUR=$(get_current_node)
                if [ "$CUR" = "DIRECT" ]; then
                    FIRST=$(get_nodes | head -1)
                    [ -n "$FIRST" ] && switch_node "$FIRST"
                fi
                echo "已切换: 全局模式 (global), 节点: $(get_current_node)"
                ;;

            *)
                echo "无效模式: $CMODE (可选: direct / proxy / global)"
                exit 1
                ;;
        esac
        ;;

    update)
        echo "正在更新订阅..."
        curl -sf -X PUT "$API/providers/proxies/airport" \
            -H "Content-Type: application/json" -d '{}' > /dev/null
        sleep 3
        REGIONS=$(get_nodes | python3 -c "
import sys, re
from collections import Counter
regions = Counter()
for line in sys.stdin:
    name = line.strip()
    m = re.match(r'^[\w-]*?([A-Z]{2,3})[\s\-_]', name)
    regions[m.group(1) if m else 'OTHER'] += 1
for r, c in regions.most_common():
    print(f'  {r}: {c}个')
" 2>/dev/null)
        echo "订阅已更新"
        echo "可用区域及节点数:"
        echo "$REGIONS"
        ;;

    speed)
        FILTER="${2:-}"
        echo "正在测速, 请稍候 (约 5-10 秒)..."
        DELAYS=$(curl -sf "$API/group/PROXY/delay?timeout=5000&url=https://www.gstatic.com/generate_204" 2>/dev/null)
        if [ -z "$DELAYS" ]; then
            echo "测速失败, API 不可达"
            exit 1
        fi

        echo "$DELAYS" | python3 -c "
import sys, json

delays = json.load(sys.stdin)
delays.pop('DIRECT', None)

filter_str = '${FILTER}'.upper()
if filter_str:
    delays = {k: v for k, v in delays.items() if filter_str in k.upper()}
    if not delays:
        print(f'没有匹配区域 \"{filter_str}\" 的节点')
        exit(0)

ranked = sorted(delays.items(), key=lambda x: x[1])
topn = min(30, len(ranked))

print()
print(f'  {\"排名\":4s}  {\"节点\":40s}  {\"延迟\"}')
print(f'  {\"-\"*4}  {\"-\"*40}  {\"-\"*8}')
for i, (name, delay) in enumerate(ranked[:topn], 1):
    if delay < 300:
        color = '\033[0;32m'
    elif delay < 600:
        color = '\033[1;33m'
    elif delay < 1000:
        color = '\033[0;33m'
    else:
        color = '\033[0;31m'
    print(f'  {i:4d}  {name:40s}  {color}{delay:5d}ms\033[0m')

if len(ranked) > topn:
    print(f'  ... 还有 {len(ranked) - topn} 个节点')

valid = [d for _, d in ranked if d > 0]
if valid:
    avg = sum(valid) // len(valid)
    best = ranked[0]
    print(f'\n  最快: {best[0]} ({best[1]}ms)')
    print(f'  平均: {avg}ms  ({len(valid)} 个节点)')
    print(f'  切换到最快: proxy fastest{\" \" + filter_str if filter_str else \"\"}')
print()
" 2>/dev/null || echo "解析失败"
        ;;

    fastest)
        FILTER="${2:-}"
        echo "正在测速并切换, 请稍候 (约 5-10 秒)..."
        DELAYS=$(curl -sf "$API/group/PROXY/delay?timeout=5000&url=https://www.gstatic.com/generate_204" 2>/dev/null)
        if [ -z "$DELAYS" ]; then
            echo "测速失败"
            exit 1
        fi

        BEST=$(echo "$DELAYS" | python3 -c "
import sys, json
delays = json.load(sys.stdin)
delays.pop('DIRECT', None)
filter_str = '${FILTER}'.upper()
if filter_str:
    delays = {k: v for k, v in delays.items() if filter_str in k.upper()}
if not delays:
    exit(1)
best = min(delays.items(), key=lambda x: x[1])
print(best[0])
" 2>/dev/null)

        if [ -z "$BEST" ]; then
            [ -n "$FILTER" ] && echo "没有匹配区域 \"$FILTER\" 的节点" || echo "无可用节点"
            exit 1
        fi

        switch_node "$BEST"
        switch_global "PROXY"
        echo "已切换到最快节点: $BEST"
        ( sleep 1
          curl -sf --proxy "http://127.0.0.1:${PROXY_PORT}" --connect-timeout 5 \
              https://www.google.com -o /dev/null -w "Google: HTTP %{http_code} %{time_total}s\n" 2>/dev/null
        ) &
        ;;

    help|--help|-h)
        echo "proxy - 代理管理工具"
        echo ""
        echo "用法: proxy <command> [options]"
        echo ""
        echo "  管理:"
        echo "    start              启动代理后台服务"
        echo "    stop               停止代理"
        echo "    restart            重启代理"
        echo "    log                查看运行日志"
        echo "    update             更新订阅 (拉取最新节点)"
        echo ""
        echo "  查看:"
        echo "    info               查看当前状态 & 连通性"
        echo "    list               按区域分组列出所有节点"
        echo "    regions            列出可用区域及节点数"
        echo "    speed [区域]       测速全部节点并排名"
        echo ""
        echo "  切换:"
        echo "    mode               查看当前模式"
        echo "    mode direct        直连模式 — 所有流量不走代理"
        echo "    mode proxy         规则模式 — 按规则路由"
        echo "    mode global        全局模式 — 所有流量强行走代理"
        echo "    switch <节点名>    切换到指定节点"
        echo "    fastest [区域]     自动测速并切换到最快节点"
        echo ""
        echo "示例:"
        echo "    proxy speed         # 测速全部节点并排名"
        echo "    proxy speed HK      # 只测速香港节点"
        echo "    proxy fastest       # 切换到最快的节点"
        echo "    proxy mode global   # 全局代理模式"
        echo "    proxy mode proxy    # 规则代理模式"
        echo "    proxy mode direct   # 直连模式"
        ;;

    *)
        ARG="${1:-}"
        if [ -n "$ARG" ]; then
            MATCHES=$(get_nodes | grep -i "$ARG" 2>/dev/null || true)
            MATCH_COUNT=$(echo "$MATCHES" | grep -c . 2>/dev/null || echo 0)
            if [ "$MATCH_COUNT" -eq 1 ]; then
                switch_node "$(echo "$MATCHES" | head -1)"
                switch_global "PROXY"
                echo "已切换到: $(echo "$MATCHES" | head -1)"
                exit 0
            elif [ "$MATCH_COUNT" -gt 1 ]; then
                echo "匹配到多个节点, 请明确指定:"
                echo "$MATCHES" | head -10 | while read n; do echo "  $n"; done
                if [ "$MATCH_COUNT" -gt 10 ]; then echo "  ... 还有 $((MATCH_COUNT - 10)) 个"; fi
                exit 1
            fi
        fi
        echo "未知命令: ${1:-}"
        echo "使用 'proxy help' 查看帮助"
        exit 1
        ;;
esac
