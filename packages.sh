#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# 应用显示名与 flatpak id 的对照，新增应用时添加一行
FLATPAK_APPS=(
    "com.visualstudio.code|VS Code"
    "org.localsend.localsend_app|LocalSend"
)

die() { printf '错误：%s\n' "$1" >&2; exit 1; }

dnf_install() {
    local missing=() p
    for p in "$@"; do
        rpm -q "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -eq 0 ]; then
        printf '  [已有] %s\n' "$*"
        return 0
    fi
    printf '  [安装] %s\n' "${missing[*]}"
    sudo dnf install -y "${missing[@]}"
}

copr_enable() {
    local project="$1"
    if dnf copr list 2>/dev/null | grep -qx "copr.fedorainfracloud.org/$project"; then
        printf '  [已有] COPR %s\n' "$project"
        return 0
    fi
    printf '  [启用] COPR %s\n' "$project"
    sudo dnf copr enable -y "$project"
}

git_clone() {
    local url="$1" dest="$2" label="$3"
    if [ -d "$dest/.git" ]; then
        printf '  [已有] %s\n' "$label"
        return 0
    fi
    printf '  [克隆] %s\n' "$label"
    git clone --depth 1 "$url" "$dest" || {
        rm -rf "$dest"
        die "克隆失败：$label"
    }
}

flatpak_install() {
    local app label
    while IFS='|' read -r app label; do
        if flatpak info "$app" >/dev/null 2>&1; then
            printf '  [已有] %s\n' "$label"
        else
            printf '  [安装] %s\n' "$label"
            flatpak install -y flathub "$app"
        fi
    done < <(printf '%s\n' "${FLATPAK_APPS[@]}")
}

install_tools() {
    printf '==> 基础工具\n'
    dnf_install git gh zsh btop chezmoi
    copr_enable scottames/ghostty
    dnf_install ghostty
    git_clone https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" oh-my-zsh
    git_clone https://github.com/romkatv/powerlevel10k.git \
        "$ZSH_CUSTOM/themes/powerlevel10k" powerlevel10k
    git_clone https://github.com/zsh-users/zsh-autosuggestions \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions" zsh-autosuggestions
    git_clone https://github.com/zsh-users/zsh-syntax-highlighting \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" zsh-syntax-highlighting
    if [ "$SHELL" = "$(command -v zsh)" ]; then
        printf '  [已有] 默认 shell 为 zsh\n'
    else
        printf '  [改动] 默认 shell 改为 zsh\n'
        chsh -s "$(command -v zsh)"
    fi
}

install_ime() {
    printf '==> 输入法\n'
    dnf_install fcitx5 fcitx5-chinese-addons fcitx5-configtool fcitx5-gtk fcitx5-qt5 fcitx5-qt6
}

install_apps() {
    printf '==> 应用\n'
    copr_enable ilyaz/LACT
    dnf_install lact
    if systemctl is-enabled --quiet lactd; then
        printf '  [已有] lactd 已开机自启\n'
    else
        printf '  [改动] 设置 lactd 开机自启\n'
        sudo systemctl enable --now lactd
    fi
    dnf_install fedora-workstation-repositories
    if grep -qE '^enabled=1' /etc/yum.repos.d/google-chrome.repo 2>/dev/null; then
        printf '  [已有] google-chrome 仓库已启用\n'
    else
        printf '  [启用] google-chrome 仓库\n'
        sudo dnf config-manager setopt google-chrome.enabled=1
    fi
    dnf_install google-chrome-stable
    flatpak_install
}

install_theme() {
    printf '==> 主题配套组件\n'
    "$ROOT/desktop.sh" kvitals
}

install_tools
install_ime
install_apps
install_theme
printf '==> 完成\n'
