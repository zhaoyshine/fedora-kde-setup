#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$ROOT/macos-tahoe-liquid-kde"
PERSONAL_DIR="$ROOT/desktop-personal"
APPLY_PY="$ROOT/apply-personal.py"
CONFIG_DIR="$HOME/.config"

KV_ID="org.kde.plasma.kvitals"
KV_VER="v3.1.2"
KV_URL="https://github.com/yassine20011/kvitals/releases/download/$KV_VER/$KV_ID-$KV_VER.plasmoid"
KV_SHA="14126ce5ff447236566bee529db0850495d3bfa4c0b520c74c553d347364abac"
KV_PKG="$ROOT/kvitals/$KV_ID-$KV_VER.plasmoid"
KV_DEST="$HOME/.local/share/plasma/plasmoids/$KV_ID"

TRANSPARENCY=90
DOCK=12

die() { printf '错误：%s\n' "$1" >&2; exit 1; }

kvitals_fetch() {
    if [ -f "$KV_PKG" ] && \
       [ "$(sha256sum "$KV_PKG" | cut -d' ' -f1)" = "$KV_SHA" ]; then
        printf '  [缓存命中] KVitals %s\n' "$KV_VER"
        return 0
    fi
    mkdir -p "$(dirname "$KV_PKG")"
    printf '  [下载] KVitals %s\n' "$KV_VER"
    curl -fL --retry 5 -o "$KV_PKG.part" "$KV_URL" || {
        rm -f "$KV_PKG.part"
        die "下载失败。GitHub 走不通的话先跑 ssr 开代理再试"
    }
    echo "$KV_SHA  $KV_PKG.part" | sha256sum -c - >/dev/null || {
        rm -f "$KV_PKG.part"
        die "校验失败，已丢弃"
    }
    mv "$KV_PKG.part" "$KV_PKG"
    printf '  已下载并校验\n'
}

kvitals_install() {
    if [ -d "$KV_DEST" ]; then
        printf '  KVitals 已装，跳过\n'
        return 0
    fi
    kvitals_fetch
    printf '  装 KVitals %s\n' "$KV_VER"
    kpackagetool6 --type Plasma/Applet --install "$KV_PKG"
}

stop_plasmashell() {
    pgrep -x plasmashell >/dev/null || return 0
    kquitapp6 plasmashell >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do
        pgrep -x plasmashell >/dev/null || return 0
        sleep 0.25
    done
    printf '  plasmashell 不肯退，强杀\n' >&2
    pkill -x plasmashell || true
    sleep 1
}

start_plasmashell() {
    setsid plasmashell --replace >/dev/null 2>&1 </dev/null &
    sleep 1
}

apply_transparency() {
    local script="$REPO/src/scripts/set-transparency"
    [ -f "$script" ] || die "找不到 $script（上游仓库是不是没拉全？）"
    printf '  应用透明度 %s%%（dock %s%%）\n' "$TRANSPARENCY" "$DOCK"
    python3 "$script" "$TRANSPARENCY" --dock "$DOCK" --apply
}

cmd_restart() {
    printf '==> 重启 plasmashell\n'
    stop_plasmashell
    start_plasmashell
}

cmd_kvitals() {
    kvitals_install
}

apply_personal_files() {
    local src name dst any=0
    for src in "$PERSONAL_DIR"/*; do
        [ -f "$src" ] || continue
        any=1
        name="$(basename "$src")"
        dst="$CONFIG_DIR/$name"
        if [ ! -f "$dst" ]; then
            printf '  跳过 %s：%s 不存在\n' "$name" "$dst"
            continue
        fi
        printf '%s\n' "$name"
        python3 "$APPLY_PY" "$src" "$dst"
    done
    [ "$any" = 1 ] || die "$PERSONAL_DIR 里没有配置文件"
}

cmd_personal() {
    printf '==> 确保 KVitals 在\n'
    kvitals_install

    mkdir -p "$CONFIG_DIR"
    local bak="$CONFIG_DIR/plasma-org.kde.plasma.desktop-appletsrc.bak.$(date +%Y%m%d-%H%M%S)"
    cp -f "$CONFIG_DIR/plasma-org.kde.plasma.desktop-appletsrc" "$bak" 2>/dev/null || true
    printf '  改之前的配置备份到 %s\n' "${bak#"$HOME"/}"

    printf '==> 应用个人配置（只写 desktop-personal/ 里有的键）\n'
    stop_plasmashell
    apply_personal_files
    start_plasmashell

    printf '==> 主题调参\n'
    apply_transparency
}

case "${1:-}" in
    personal) cmd_personal ;;
    kvitals)  cmd_kvitals ;;
    restart)  cmd_restart ;;
    *) printf '用法：%s {personal|kvitals|restart}\n' "${BASH_SOURCE[0]##*/}" >&2; exit 1 ;;
esac
