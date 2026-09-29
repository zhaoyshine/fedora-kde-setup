#!/usr/bin/env bash

set -euo pipefail

DNF_CONF=/etc/dnf/dnf.conf
FSTAB=/etc/fstab
ZRAM_CONF=/etc/systemd/zram-generator.conf
ZRAM_UNIT=systemd-zram-setup@zram0.service

die() { printf '错误：%s\n' "$1" >&2; exit 1; }

dnf_conf_set() {
    local key="$1" want="$2" current
    current="$(grep -E "^${key}=" "$DNF_CONF" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
    if [ "$current" = "$want" ]; then
        printf '  [已有] %s=%s\n' "$key" "$want"
    elif [ -n "$current" ]; then
        printf '  [保留] %s=%s（目标 %s，保持原值）\n' "$key" "$current" "$want"
    else
        printf '  [改动] %s=%s\n' "$key" "$want"
        printf '%s=%s\n' "$key" "$want" | sudo tee -a "$DNF_CONF" >/dev/null
    fi
}

flatpak_remote_ensure() {
    if flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub; then
        printf '  [已有] flathub remote\n'
    elif flatpak remotes --user --columns=name 2>/dev/null | grep -qx flathub; then
        printf '  [已有] flathub remote（用户级）\n'
    else
        printf '  [添加] flathub remote\n'
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
}

flatpak_remote_drop() {
    local name="$1"
    if flatpak remotes --system --columns=name 2>/dev/null | grep -qx "$name"; then
        printf '  [删除] %s remote（仅保留 flathub）\n' "$name"
        sudo flatpak remote-delete "$name"
    elif flatpak remotes --user --columns=name 2>/dev/null | grep -qx "$name"; then
        printf '  [删除] %s remote（用户级）\n' "$name"
        flatpak remote-delete "$name"
    else
        printf '  [跳过] %s remote 不存在\n' "$name"
    fi
}

backup_file() {
    local src="$1"
    local dst="$src.bak-$(date +%F)"
    [ -e "$dst" ] && { printf '  [已有] 备份 %s\n' "$dst"; return 0; }
    printf '  [备份] %s\n' "$dst"
    sudo cp -a "$src" "$dst"
}

setup_zram() {
    printf '==> 关闭 zram\n'
    if [ ! -e "$ZRAM_CONF" ]; then
        printf '  [改动] 创建空 %s（zram-generator 以空配置为关闭）\n' "$ZRAM_CONF"
        sudo touch "$ZRAM_CONF"
    elif [ -s "$ZRAM_CONF" ]; then
        backup_file "$ZRAM_CONF"
        printf '  [改动] 清空 %s\n' "$ZRAM_CONF"
        sudo truncate -s0 "$ZRAM_CONF"
    else
        printf '  [已有] %s 为空\n' "$ZRAM_CONF"
    fi
    if [ "$(systemctl is-enabled "$ZRAM_UNIT" 2>/dev/null)" = masked ]; then
        printf '  [已有] %s 已 mask\n' "$ZRAM_UNIT"
    else
        printf '  [改动] mask %s\n' "$ZRAM_UNIT"
        sudo systemctl mask "$ZRAM_UNIT"
    fi
}

setup_swap() {
    printf '==> 关闭 swap\n'
    if [ -n "$(swapon --show --noheadings 2>/dev/null)" ]; then
        printf '  [改动] 关闭当前 swap\n'
        sudo swapoff -a
    else
        printf '  [已有] swap 未启用\n'
    fi
    if grep -qE '^[^#].*[[:space:]]swap[[:space:]]' "$FSTAB"; then
        backup_file "$FSTAB"
        printf '  [改动] 注释 %s 中的 swap 条目\n' "$FSTAB"
        sudo sed -i -E 's|^([^#].*[[:space:]]swap[[:space:]].*)$|# \1|' "$FSTAB"
        sudo systemctl daemon-reload
    else
        printf '  [已有] %s 无启用的 swap 条目\n' "$FSTAB"
    fi
}

setup_dnf() {
    printf '==> dnf 配置\n'
    [ -f "$DNF_CONF" ] || die "未找到 $DNF_CONF"
    dnf_conf_set max_parallel_downloads 10
    dnf_conf_set defaultyes True
}

setup_flatpak() {
    printf '==> flatpak 源\n'
    flatpak_remote_ensure
    flatpak_remote_drop fedora
    flatpak_remote_drop fedora-testing
}

setup_boot() {
    printf '==> 开机项\n'
    if systemctl is-enabled --quiet NetworkManager-wait-online.service; then
        printf '  [改动] 禁用 NetworkManager-wait-online.service\n'
        sudo systemctl disable NetworkManager-wait-online.service
    else
        printf '  [已有] NetworkManager-wait-online.service 已禁用\n'
    fi
}

setup_dnf
setup_flatpak
setup_boot
setup_zram
setup_swap
printf '==> 完成\n'
