#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$ROOT/dotfiles"
SYSTEM_SRC="$ROOT/system"
CONFIG_DIR="$HOME/.config"

MANAGED_FILES=(
    "$CONFIG_DIR/plasma-org.kde.plasma.desktop-appletsrc"
    "$CONFIG_DIR/plasmashellrc"
    "$CONFIG_DIR/plasmarc"
    "$CONFIG_DIR/kdeglobals"
    "$CONFIG_DIR/kglobalshortcutsrc"
    "$CONFIG_DIR/kscreenlockerrc"
    "$CONFIG_DIR/fcitx5/config"
    "$CONFIG_DIR/fcitx5/profile"
    "$CONFIG_DIR/environment.d/fcitx5.conf"
    "$CONFIG_DIR/ghostty/config.ghostty"
    "$CONFIG_DIR/kxkbrc"
    "$CONFIG_DIR/kwinrc"
    "$CONFIG_DIR/kwinrulesrc"
    "$CONFIG_DIR/powerdevilrc"
)
SYSTEM_PATHS=(
    /etc/udev/rules.d
    /etc/sysctl.d/99-swap.conf
    /etc/systemd/zram-generator.conf
)

# KVitals 插件 id 与版本，升级时同步更新下方下载地址和校验和
KV_ID="org.kde.plasma.kvitals"
KV_VER="v3.1.2"
KV_URL="https://github.com/yassine20011/kvitals/releases/download/$KV_VER/$KV_ID-$KV_VER.plasmoid"
KV_SHA="14126ce5ff447236566bee529db0850495d3bfa4c0b520c74c553d347364abac"
KV_PKG="$ROOT/kvitals/$KV_ID-$KV_VER.plasmoid"
KV_DEST="$HOME/.local/share/plasma/plasmoids/$KV_ID"

# MouseTiler 脚本 id 与版本，升级时同步更新下方下载地址和校验和
MT_ID="mousetiler"
MT_VER="v6.5.0"
MT_URL="https://github.com/rxappdev/MouseTiler/releases/download/$MT_VER/$MT_ID.kwinscript"
MT_SHA="b8e9237ecae99856ebea888926fb95250e497f3856519d8f722198678a6b25d6"
MT_PKG="$ROOT/mousetiler/$MT_ID-$MT_VER.kwinscript"
MT_DEST="$HOME/.local/share/kwin/scripts/$MT_ID"

# swap 设置由 backup 写入 swap.conf，restore 据此重建；/etc/fstab 其余条目与目标机绑定
SWAP_CONF="$ROOT/swap.conf"
SWAPFILE=""
SWAP_SIZE=""
SWAP_ENTRY=""
[ -f "$SWAP_CONF" ] && . "$SWAP_CONF"

QDBUS=""

die() { printf '错误：%s\n' "$1" >&2; exit 1; }

ensure_chezmoi() {
    command -v chezmoi >/dev/null || die "未找到 chezmoi，请先安装：sudo dnf install chezmoi"
    [ -d "$DOTFILES" ] || die "未找到 $DOTFILES，仓库不完整"
    [ -d "$SYSTEM_SRC" ] || die "未找到 $SYSTEM_SRC，仓库不完整"
}

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
        die "下载失败，若无法访问 GitHub 请先启动 ssr 代理后重试"
    }
    echo "$KV_SHA  $KV_PKG.part" | sha256sum -c - >/dev/null || {
        rm -f "$KV_PKG.part"
        die "校验失败，文件已删除"
    }
    mv "$KV_PKG.part" "$KV_PKG"
    printf '  [完成] 下载并校验通过\n'
}

kvitals_install() {
    if [ -d "$KV_DEST" ]; then
        printf '  [跳过] KVitals 已安装\n'
        return 0
    fi
    kvitals_fetch
    printf '  [安装] KVitals %s\n' "$KV_VER"
    kpackagetool6 --type Plasma/Applet --install "$KV_PKG"
}

mousetiler_fetch() {
    if [ -f "$MT_PKG" ] && \
       [ "$(sha256sum "$MT_PKG" | cut -d' ' -f1)" = "$MT_SHA" ]; then
        printf '  [缓存命中] MouseTiler %s\n' "$MT_VER"
        return 0
    fi
    mkdir -p "$(dirname "$MT_PKG")"
    printf '  [下载] MouseTiler %s\n' "$MT_VER"
    curl -fL --retry 5 -o "$MT_PKG.part" "$MT_URL" || {
        rm -f "$MT_PKG.part"
        die "下载失败，若无法访问 GitHub 请先启动 ssr 代理后重试"
    }
    echo "$MT_SHA  $MT_PKG.part" | sha256sum -c - >/dev/null || {
        rm -f "$MT_PKG.part"
        die "校验失败，文件已删除"
    }
    mv "$MT_PKG.part" "$MT_PKG"
    printf '  [完成] 下载并校验通过\n'
}

mousetiler_install() {
    if [ -d "$MT_DEST" ]; then
        printf '  [跳过] MouseTiler 已安装\n'
        return 0
    fi
    mousetiler_fetch
    printf '  [安装] MouseTiler %s\n' "$MT_VER"
    kpackagetool6 --type KWin/Script --install "$MT_PKG"
}

stop_plasmashell() {
    pgrep -x plasmashell >/dev/null || return 0
    kquitapp6 plasmashell >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do
        pgrep -x plasmashell >/dev/null || return 0
        sleep 0.25
    done
    printf '  [警告] plasmashell 退出超时，强制结束\n' >&2
    pkill -x plasmashell || true
    sleep 1
}

start_plasmashell() {
    setsid plasmashell --replace >/dev/null 2>&1 </dev/null &
    sleep 1
}

ensure_qdbus() {
    [ -n "$QDBUS" ] && return 0
    local c
    for c in qdbus6 qdbus-qt6 qdbus; do
        if command -v "$c" >/dev/null 2>&1; then
            QDBUS="$c"
            return 0
        fi
    done
    die "未找到 qdbus，请先安装 qt6-qttools"
}

cmd_apply() {
    printf '==> 重启 plasmashell，使主题生效\n'
    stop_plasmashell
    start_plasmashell

    printf '==> 安装 KVitals\n'
    kvitals_install

    printf '==> 安装 MouseTiler\n'
    mousetiler_install

    printf '==> 重启 plasmashell，注册 plasmoid\n'
    stop_plasmashell
    start_plasmashell
}

normalize_restored_config() {
    local appletsrc="$CONFIG_DIR/plasma-org.kde.plasma.desktop-appletsrc"
    local activity home file

    if [ -f "$appletsrc" ]; then
        activity="$(ensure_qdbus >/dev/null 2>&1 && "$QDBUS" \
            org.kde.ActivityManager /ActivityManager/Activities \
            org.kde.ActivityManager.Activities.CurrentActivity 2>/dev/null || true)"
        if [ -n "$activity" ]; then
            sed -i -E "s/^activityId=[0-9a-f-]+$/activityId=$activity/" "$appletsrc"
        else
            printf '  [警告] 无法获取当前活动，activityId 置空\n' >&2
            sed -i -E 's/^activityId=[0-9a-f-]+$/activityId=/' "$appletsrc"
        fi
    fi
    home="$(printf '%s' "$HOME" | sed 's/[\\&|]/\\&/g')"
    for file in "$appletsrc" "$CONFIG_DIR/plasmarc" "$CONFIG_DIR/ghostty/config.ghostty"; do
        [ -f "$file" ] && sed -i -E "s|/home/[^/\"]+/|$home/|g" "$file"
    done
}

ensure_swapfile() {
    [ -n "$SWAPFILE" ] || { printf '  [跳过] swap.conf 未记录 swapfile\n'; return 0; }
    if [ ! -f "$SWAPFILE" ]; then
        printf '  [创建] swapfile %s（%s）\n' "$SWAPFILE" "$SWAP_SIZE"
        local fstype
        fstype="$(findmnt -no FSTYPE --target "$(dirname "$SWAPFILE")")"
        if [ "$fstype" = btrfs ]; then
            sudo btrfs filesystem mkswapfile --size "$SWAP_SIZE" "$SWAPFILE"
        else
            sudo truncate -s 0 "$SWAPFILE"
            sudo fallocate -l "$SWAP_SIZE" "$SWAPFILE"
            sudo mkswap "$SWAPFILE"
        fi
        sudo chmod 600 "$SWAPFILE"
    fi
    if ! awk -v f="$SWAPFILE" '$1 == f && $3 == "swap" { found = 1 } END { exit !found }' /etc/fstab; then
        printf '  [追加] /etc/fstab swap 条目\n'
        printf '%s\n' "$SWAP_ENTRY" | sudo tee -a /etc/fstab >/dev/null
    fi
}

write_swap_conf() {
    local line file size
    line=""
    file=""
    while IFS= read -r line; do
        file="${line%%[[:space:]]*}"
        [ -f "$file" ] && break
        line=""
    done < <(awk '$1 ~ /^\// && $3 == "swap"' /etc/fstab)
    if [ -z "$line" ]; then
        printf '  [记录] /etc/fstab 无 swapfile 条目，清空 swap.conf\n'
        printf 'SWAPFILE=""\nSWAP_SIZE=""\nSWAP_ENTRY=""\n' > "$SWAP_CONF"
        return 0
    fi
    size="$(stat -c %s "$file" 2>/dev/null || true)"
    if [ -z "$size" ]; then
        printf '  [警告] 无法读取 %s 大小，swap.conf 未更新\n' "$file" >&2
        return 0
    fi
    size="$(numfmt --to=iec-i --suffix=B "$size")"
    printf 'SWAPFILE=%q\nSWAP_SIZE=%q\nSWAP_ENTRY=%q\n' "$file" "$size" "$line" > "$SWAP_CONF"
    printf '  [记录] swap：%s %s\n' "$file" "$size"
}

snapshot_current_state() {
    local dir="$HOME/.local/state/fedora-kde-setup/pre-restore-$(date +%Y%m%d-%H%M%S)"
    local src
    mkdir -p "$dir"
    for src in "${MANAGED_FILES[@]}"; do
        [ -e "$src" ] && cp -a --parents "$src" "$dir"
    done
    for src in "${SYSTEM_PATHS[@]}" /etc/fstab; do
        [ -e "$src" ] && sudo cp -a --parents "$src" "$dir"
    done
    sudo chown -R "$(id -u):$(id -g)" "$dir"
    printf '  [快照] 恢复前状态：%s\n' "$dir"
}

cmd_restore() {
    ensure_chezmoi

    local drift answer
    if ! drift="$(chezmoi -S "$DOTFILES" diff 2>&1)"; then
        die "chezmoi diff 执行失败"
    fi
    if ! drift+="$(chezmoi -S "$SYSTEM_SRC" --destination / diff 2>&1)"; then
        die "系统配置 chezmoi diff 执行失败"
    fi
    if [ -n "$drift" ]; then
        printf '==> 检测到漂移：本地配置和仓库快照不一致\n'
        printf '（每行截断至 200 字符，完整 diff 执行 chezmoi -S dotfiles diff 与 chezmoi -S system --destination / diff 查看）\n'
        printf '%s\n' "$drift" | sed 's/^/  /' | cut -c1-200
        printf '继续将用仓库快照覆盖本地配置，建议先执行 make backup 固化改动\n'
        printf '继续覆盖？(y/N) '
        read -r answer
        case "$answer" in
            y|Y|yes|YES) ;;
            *) die "已取消，本地配置未修改" ;;
        esac
    fi

    printf '==> 恢复配置快照\n'
    stop_plasmashell
    snapshot_current_state
    chezmoi -S "$DOTFILES" apply --force
    printf '==> 校正恢复配置的本机绑定\n'
    normalize_restored_config
    start_plasmashell

    printf '==> 恢复系统配置快照\n'
    sudo chezmoi -S "$SYSTEM_SRC" --destination / apply --force
    sudo udevadm control --reload
    sudo udevadm trigger --action=change --subsystem-match=hwmon --attr-match=name=xe
    sudo udevadm trigger --action=add --subsystem-match=pci \
        --attr-match=vendor=0x8086 --attr-match=device=0x4f90
    sudo sysctl --system
    ensure_swapfile
    sudo systemctl daemon-reload
    sudo swapoff -a 2>/dev/null || true
    sudo swapon -a || die "swap 启用失败"
}

cmd_backup() {
    ensure_chezmoi
    printf '==> 将当前配置回写至仓库快照\n'
    local src
    for src in "${MANAGED_FILES[@]}"; do
        if [ -f "$src" ]; then
            chezmoi -S "$DOTFILES" add "$src"
        else
            printf '  [跳过] %s 不存在\n' "$src"
        fi
    done
    printf '==> 将系统配置回写至仓库快照\n'
    for src in "${SYSTEM_PATHS[@]}"; do
        if [ -e "$src" ]; then
            chezmoi -S "$SYSTEM_SRC" --destination / add "$src"
        else
            printf '  [跳过] %s 不存在\n' "$src"
        fi
    done
    printf '==> 将 swap 设置回写至仓库快照\n'
    write_swap_conf
    printf '==> 快照已更新，仓库改动如下，请审阅后执行 git commit：\n'
    git -C "$ROOT" status --short -- dotfiles/ system/ swap.conf
    git -C "$ROOT" diff -- dotfiles/ system/ swap.conf
    printf '（无输出表示快照未变更，无需提交）\n'
}

case "${1:-}" in
    apply)      cmd_apply ;;
    kvitals)    kvitals_install ;;
    mousetiler) mousetiler_install ;;
    restore)    cmd_restore ;;
    backup)     cmd_backup ;;
    *) printf '用法：%s {apply|kvitals|mousetiler|restore|backup}\n' "${BASH_SOURCE[0]##*/}" >&2; exit 1 ;;
esac
