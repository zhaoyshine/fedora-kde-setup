#!/usr/bin/env bash

set -euo pipefail

DNF_CONF=/etc/dnf/dnf.conf

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
printf '==> 完成\n'
