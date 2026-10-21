#!/usr/bin/env bash
# 当前文件：在一台 Linux 云服务器上一键装好 Folia Docker 全栈（网页、网易云、QQ 音乐、酷狗接口），没有域名时用 http://公网IP:端口 访问。
# 可以重复运行：已有的 .env 原样保留，只更新 compose.yaml 并拉取最新镜像。
# 用法（root 或能 sudo 的用户）：bash install-vps.sh
# 可选环境变量：FOLIA_DIR（安装目录，默认 /opt/folia）、FOLIA_HTTP_PORT（网页端口，默认 18080）、
#              FOLIA_REGISTRY_MIRROR（Docker Hub 镜像加速地址，逗号分隔；国内服务器连不上 Docker Hub 时用）。
set -euo pipefail

INSTALL_DIR="${FOLIA_DIR:-/opt/folia}"
HTTP_PORT="${FOLIA_HTTP_PORT:-18080}"
COMPOSE_SOURCES=(
    "https://raw.githubusercontent.com/chthollyphile/folia-major/main/deploy/docker/compose.yaml"
    "https://cdn.jsdelivr.net/gh/chthollyphile/folia-major@main/deploy/docker/compose.yaml"
    "https://fastly.jsdelivr.net/gh/chthollyphile/folia-major@main/deploy/docker/compose.yaml"
)
# 连不上 Docker Hub 或被限流时依次写进 registry-mirrors（前三个是国内加速站，mirror.gcr.io 给海外服务器）；这些公共加速站可用性会变，失败时用 FOLIA_REGISTRY_MIRROR 换成自己的
DEFAULT_MIRRORS="https://docker.1ms.run,https://docker.m.daocloud.io,https://docker.xuanyuan.me,https://mirror.gcr.io"

log() { printf '\033[1;36m[folia]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[folia]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[folia]\033[0m %s\n' "$*" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || die "请用 root 运行，或先安装 sudo"
    log "需要 root 权限，用 sudo 重新运行"
    exec sudo -E bash "$0" "$@"
fi

[ "$(uname -s)" = Linux ] || die "这个脚本只支持 Linux 服务器"
command -v curl >/dev/null 2>&1 || {
    log "安装 curl"
    if command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq curl
    elif command -v dnf >/dev/null 2>&1; then dnf install -y -q curl
    elif command -v yum >/dev/null 2>&1; then yum install -y -q curl
    else die "缺少 curl，请先手动安装"; fi
}

# 能连上 Docker Hub 时 /v2/ 回 401（要登录），连不上就是超时或 000
docker_hub_reachable() {
    local code
    code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://registry-1.docker.io/v2/ || true)"
    [ "$code" = 401 ] || [ "$code" = 200 ]
}

random_hex() {
    if command -v openssl >/dev/null 2>&1; then openssl rand -hex "$1"
    else head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; fi
}

install_docker() {
    log "安装 Docker"
    local mirror_args=()
    if ! docker_hub_reachable; then
        # 国内服务器：Docker 安装包从阿里云镜像下载
        mirror_args=(--mirror Aliyun)
    fi
    if curl -fsSL -m 60 https://get.docker.com -o /tmp/get-docker.sh; then
        sh /tmp/get-docker.sh ${mirror_args[@]+"${mirror_args[@]}"} || warn "官方安装脚本失败，改用系统软件源"
        rm -f /tmp/get-docker.sh
    fi
    if ! command -v docker >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq
            apt-get install -y -qq docker.io
            apt-get install -y -qq docker-compose-v2 || apt-get install -y -qq docker-compose-plugin || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q docker docker-compose-plugin || dnf install -y -q moby-engine docker-compose
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q docker docker-compose-plugin
        else
            die "装不上 Docker，请按 https://docs.docker.com/engine/install/ 手动安装后再运行本脚本"
        fi
    fi
    systemctl enable --now docker >/dev/null 2>&1 || service docker start || true
}

configure_registry_mirrors() {
    local mirrors="${FOLIA_REGISTRY_MIRROR:-$DEFAULT_MIRRORS}"
    local daemon_json=/etc/docker/daemon.json
    log "连不上 Docker Hub，配置镜像加速：$mirrors"
    mkdir -p /etc/docker
    if [ -s "$daemon_json" ]; then
        cp "$daemon_json" "$daemon_json.folia-backup"
        command -v python3 >/dev/null 2>&1 || die "$daemon_json 已有内容且没有 python3 合并，请手动把加速地址加进 registry-mirrors"
        python3 - "$daemon_json" "$mirrors" <<'PY'
import json, sys
path, mirrors = sys.argv[1], [m for m in sys.argv[2].split(',') if m]
with open(path) as f:
    config = json.load(f)
config['registry-mirrors'] = mirrors + [m for m in config.get('registry-mirrors', []) if m not in mirrors]
with open(path, 'w') as f:
    json.dump(config, f, indent=2)
PY
    else
        printf '{\n  "registry-mirrors": [%s]\n}\n' "$(printf '%s' "$mirrors" | sed 's/[^,][^,]*/"&"/g; s/,/, /g')" > "$daemon_json"
    fi
    systemctl restart docker 2>/dev/null || service docker restart
    MIRRORS_CONFIGURED=true
}

download_compose() {
    local target="$INSTALL_DIR/compose.yaml" tmp="$INSTALL_DIR/compose.yaml.download"
    for url in "${COMPOSE_SOURCES[@]}"; do
        if curl -fsSL -m 30 "$url" -o "$tmp" && grep -q 'folia-web' "$tmp"; then
            mv "$tmp" "$target"
            log "已下载 compose.yaml（$url）"
            return 0
        fi
        warn "下载失败：$url"
    done
    rm -f "$tmp"
    [ -s "$target" ] && { warn "沿用已有的 compose.yaml"; return 0; }
    die "compose.yaml 下载不下来，请检查服务器能否访问 GitHub 或 jsDelivr"
}

write_env() {
    local env_file="$INSTALL_DIR/.env"
    if [ -s "$env_file" ]; then
        log "保留已有的 $env_file"
        return 0
    fi
    log "生成 $env_file"
    cat > "$env_file" <<EOF
# 由 install-vps.sh 生成。改完执行：cd $INSTALL_DIR && docker compose up -d
FOLIA_IMAGE_NAMESPACE=papersman

FOLIA_HTTP_BIND=0.0.0.0
FOLIA_HTTP_PORT=$HTTP_PORT
FOLIA_AI_PROVIDER=google
FOLIA_FORWARD_CLIENT_IP=false
ENABLE_GENERAL_UNBLOCK=false

# QQ 音乐登录态加密存进 qq-api-state 卷，重启容器不用重新扫码。密钥不要改，改了要重新登录。
QQ_AUTH_SESSION_PATH=/app/.auth-state/qq-session.enc
QQ_SESSION_SECRET=$(random_hex 32)

NAVIDROME_URL=
NAVIDROME_USERNAME=
NAVIDROME_PASSWORD=
NAVIDROME_PRESET_ALLOW=private
FOLIA_TRUSTED_PROXIES=

GEMINI_API_KEY=
OPENAI_API_KEY=
OPENAI_API_URL=https://api.openai.com/v1
OPENAI_API_MODEL=gpt-4o
OPENAI_API_TEMPERATURE=0.7

# 同步服务只在本机监听，不对公网开放；要用多设备同步再改成 0.0.0.0 并放行端口
FOLIA_SYNC_BIND=127.0.0.1
FOLIA_SYNC_PORT=13000
FOLIA_SYNC_DATA_DIR=./data/sync
SYNC_TOKEN=$(random_hex 32)
DASHBOARD_TOKEN=
EOF
    chmod 600 "$env_file"
}

open_firewall() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
        ufw allow "$HTTP_PORT/tcp" >/dev/null && log "ufw 已放行 $HTTP_PORT/tcp"
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="$HTTP_PORT/tcp" >/dev/null && firewall-cmd --reload >/dev/null \
            && log "firewalld 已放行 $HTTP_PORT/tcp"
    fi
}

all_images_present() {
    local image
    for image in $(docker compose config --images); do
        docker image inspect "$image" >/dev/null 2>&1 || return 1
    done
}

pull_images() {
    local attempt
    for attempt in 1 2 3; do
        if docker compose pull; then return 0; fi
        # Docker Hub 限流（429）或连不上：第一次失败后换成镜像加速再试
        if [ "$attempt" = 1 ] && [ "${MIRRORS_CONFIGURED:-}" != true ]; then
            configure_registry_mirrors
        else
            warn "镜像拉取失败（第 $attempt 次），10 秒后重试"
            sleep 10
        fi
    done
    if all_images_present; then
        warn "这次没拉到新镜像，继续用本机已有的版本"
        return 0
    fi
    die "镜像拉不下来。国内服务器请换一个能用的加速地址后重跑：FOLIA_REGISTRY_MIRROR=https://你的加速地址 bash $0"
}

check_endpoint() {
    local path="$1" name="$2" code
    code="$(curl -s -m 15 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$HTTP_PORT$path" || true)"
    if [ "$code" = 200 ]; then log "  $name 正常"
    else warn "  $name 返回 $code（路径 $path）"; fi
}

main() {
    if ! command -v docker >/dev/null 2>&1; then
        install_docker
    fi
    docker info >/dev/null 2>&1 || { systemctl start docker 2>/dev/null || true; sleep 3; }
    docker info >/dev/null 2>&1 || die "Docker 没有运行起来，请检查 systemctl status docker"
    docker compose version >/dev/null 2>&1 || die "缺少 docker compose 插件，请安装 docker-compose-plugin 后重跑"

    if [ -n "${FOLIA_REGISTRY_MIRROR:-}" ] || ! docker_hub_reachable; then
        configure_registry_mirrors
    fi

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    download_compose
    write_env

    docker compose config -q
    pull_images
    log "启动 Folia（第一次启动要等网易云接口初始化，大约一两分钟）"
    if ! docker compose up -d --wait --wait-timeout 300; then
        docker compose ps
        die "有服务没启动成功，用 cd $INSTALL_DIR && docker compose logs 查看原因"
    fi

    open_firewall

    log "自检："
    check_endpoint /healthz "网页网关"
    check_endpoint /api/healthz "Folia Web API"
    check_endpoint /netease/ "网易云接口"
    check_endpoint /kugou/ "酷狗接口"
    check_endpoint /qq/login/status "QQ 音乐接口"

    local ip
    ip="$(curl -s -m 8 https://api.ipify.org || curl -s -m 8 https://ip.sb || true)"
    ip="${ip:-<服务器公网IP>}"
    cat <<EOF

========================================================
 Folia 已经部署好了
 地址：http://$ip:$HTTP_PORT

 1. 到云服务器控制台的「安全组 / 防火墙」里放行 TCP $HTTP_PORT 端口（入方向）
 2. 先用手机 Safari 打开上面的地址，确认能登录、能看到歌单
 3. iOS App 第一次打开时填这个地址

 安装目录：$INSTALL_DIR（配置在 .env）
 查看状态：cd $INSTALL_DIR && docker compose ps
 查看日志：cd $INSTALL_DIR && docker compose logs -f --tail=100
 更新版本：重新运行本脚本，或 cd $INSTALL_DIR && docker compose pull && docker compose up -d
========================================================
EOF
}

main "$@"
