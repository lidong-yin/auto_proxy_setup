# proxy-setup — 服务器代理一键部署

适用于无持久化存储的虚拟/容器服务器，重启后一键恢复代理环境。

## 快速开始

```bash
# 1. 克隆项目
git clone https://github.com/lidong-yin/auto_proxy_setup.git
cd auto_proxy_setup

# 2. 编辑配置（只改一行订阅链接即可）
vim config/config.sh

# 3. 一键安装
sudo bash setup.sh
```

安装完成后，使用 `proxy` 命令管理代理。

## proxy 命令速查

```bash
# 管理
proxy start           # 启动代理
proxy stop            # 停止代理
proxy restart         # 重启代理
proxy update          # 更新订阅
proxy log             # 查看运行日志

# 查看
proxy info            # 当前状态 & Google/YouTube 连通性
proxy list            # 按区域分组列出所有节点
proxy regions         # 可用区域及节点数量

# 测速
proxy speed           # 测速全部节点，按延迟排名
proxy speed HK        # 只测速指定区域节点
proxy fastest         # 自动测速并切换到最快节点
proxy fastest JP      # 只测指定区域，切到最快的

# 模式切换
proxy mode            # 查看当前模式 (mihomo mode + GLOBAL + PROXY)
proxy mode direct     # 直连模式 — 所有流量不走代理
proxy mode proxy      # 规则模式 — 按规则路由
proxy mode global     # 全局模式 — 所有流量强行走代理

# 节点切换
proxy switch <节点名>  # 切换到指定节点
proxy switch DIRECT   # 快速切直连
proxy HK              # 简写：自动匹配名称含 "HK" 的节点
```

## 三种网络模式

| 模式 | 命令 | 底层原理 | 行为 |
|------|------|---------|------|
| direct | `proxy mode direct` | GLOBAL=DIRECT | 所有流量直连，绕过代理 |
| proxy | `proxy mode proxy` | mode=rule, GLOBAL=PROXY | 规则路由：局域网直连，其余走代理 |
| global | `proxy mode global` | mode=global, GLOBAL=PROXY | 所有流量强行走代理（无视规则） |

```
流量 ──→ direct 模式 ──→ 直接访问
    │
    ├──→ proxy  模式 ──→ 规则匹配 ──→ 局域网 → 直接访问
    │                              └→ 其余  → PROXY → 具体节点
    │
    └──→ global 模式 ──→ 全部流量 ──→ PROXY → 具体节点
```

## 测速与节点选择

测速使用 Google gstatic 作为测速目标，约 5-10 秒完成:

| 颜色 | 延迟 | 状态 |
|------|------|------|
| 绿 | < 300ms | 极快 |
| 黄 | 300-600ms | 较快 |
| 暗黄 | 600-1000ms | 一般 |
| 红 | > 1000ms | 较慢 |

```bash
proxy speed           # 全部测速排名
proxy speed HK        # 只看香港
proxy fastest         # 自动切最快
proxy fastest JP      # 日本中最快
```

## 终端使用代理的三种方式

```bash
# 方式 1: 环境变量 (推荐)
export http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
curl https://www.google.com

# 方式 2: proxychains4 (系统命令适配)
proxychains4 curl https://www.google.com
proxychains4 git clone https://github.com/xxx/yyy.git
proxychains4 pip install some-package

# 方式 3: 直接指定
curl --proxy http://127.0.0.1:7890 https://www.google.com
```

## 配置说明

编辑 `config/config.sh`：

```bash
SUBSCRIBE_URL="https://你的订阅链接"   # 必填
PROXY_PORT=7890                       # 代理端口，默认 7890
API_PORT=9090                         # API 端口，默认 9090
DEFAULT_REGION="auto"                 # "auto" 或 "HK"/"US" 等
```

## 安装模式

### 离线安装（推荐）

`resources/` 预置了 `mihomo` 二进制（v1.19.3, 31MB），无需联网:

```bash
sudo bash setup.sh   # 秒级完成
```

### 在线下载

删除本地二进制后，脚本自动从镜像下载:

| 优先级 | 来源 | 速度 |
|--------|------|------|
| 1 | local `resources/mihomo` | 即时 |
| 2 | gh-proxy.com 镜像 | ~10s |
| 3 | ghproxy.net 镜像 | 备用 |
| 4 | GitHub 直连 | 较慢 |

## 文件结构

```
proxy-setup/
├── README.md
├── setup.sh
├── config/
│   └── config.sh
├── resources/
│   ├── .gitkeep
│   └── mihomo
└── templates/
    └── proxy.sh
```

## 常见问题

**Q: 每次服务器重启后需要做什么？**
```bash
cd proxy-setup && sudo bash setup.sh
```

**Q: 三种模式有什么区别？**
- `direct`: 所有流量直连，适合不需要代理时
- `proxy` (规则): 局域网直连、其余走代理，日常使用推荐
- `global` (全局): 所有流量走代理，适合需要强制代理时

**Q: 如何找到最快的节点？**
```bash
proxy speed          # 全部测速排名
proxy fastest        # 自动切到最快的
```

**Q: 特殊端口需求？**
编辑 `config/config.sh` 中 `PROXY_PORT` / `API_PORT`，重新运行 `sudo bash setup.sh`。
