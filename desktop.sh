#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$ROOT/macos-tahoe-liquid-kde"
DOTFILES="$ROOT/dotfiles"
CONFIG_DIR="$HOME/.config"

MANAGED_FILES=(
    "$CONFIG_DIR/plasma-org.kde.plasma.desktop-appletsrc"
    "$CONFIG_DIR/fcitx5/config"
    "$CONFIG_DIR/fcitx5/profile"
    "$CONFIG_DIR/environment.d/fcitx5.conf"
    "$CONFIG_DIR/powerdevilrc"
)

# KVitals 插件 id 与版本，升级时同步更新下方下载地址和校验和
KV_ID="org.kde.plasma.kvitals"
KV_VER="v3.1.2"
KV_URL="https://github.com/yassine20011/kvitals/releases/download/$KV_VER/$KV_ID-$KV_VER.plasmoid"
KV_SHA="14126ce5ff447236566bee529db0850495d3bfa4c0b520c74c553d347364abac"
KV_PKG="$ROOT/kvitals/$KV_ID-$KV_VER.plasmoid"
KV_DEST="$HOME/.local/share/plasma/plasmoids/$KV_ID"

# 布局默认值，仅 theme-install / theme-update 执行 apply 时生效
OPACITY=90
DOCK_OPACITY=12
DOCK_THICKNESS=64
DOCK_PINS="applications:systemsettings.desktop,applications:org.kde.discover.desktop,preferred://filemanager,applications:org.localsend.localsend_app.desktop,preferred://browser,applications:com.mitchellh.ghostty.desktop,applications:com.visualstudio.code.desktop,applications:zcode.desktop"
KV_METRICS="cpu/temp,gpu:gpu0/temp,disk:nvme0n1/temp,net/up,net/down"

QDBUS=""

die() { printf '错误：%s\n' "$1" >&2; exit 1; }

ensure_chezmoi() {
    command -v chezmoi >/dev/null || die "未找到 chezmoi，请先安装：sudo dnf install chezmoi"
    [ -d "$DOTFILES" ] || die "未找到 $DOTFILES，仓库不完整"
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

apply_transparency() {
    local script="$REPO/src/scripts/set-transparency"
    [ -f "$script" ] || { printf '  [失败] 未找到 %s（上游仓库可能未拉取完整）\n' "$script" >&2; exit 1; }
    printf '  应用透明度：全局 %s%%，dock %s%%\n' "$OPACITY" "$DOCK_OPACITY"
    python3 "$script" "$OPACITY" --dock "$DOCK_OPACITY" --apply
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

layout_script() {
    cat <<EOF
(function () {
  var metrics = "$KV_METRICS";
  var pins = "$DOCK_PINS";
  var ps = panels();
  for (var i = 0; i < ps.length; i++) {
    var p = ps[i];
    var ids = p.widgetIds;
    var dock = false;
    var bar = false;
    for (var j = 0; j < ids.length; j++) {
      var t = p.widgetById(ids[j]);
      if (!t) continue;
      if (t.type === "org.kde.mac.tahoe.liquid.icontasks") dock = true;
      if (t.type === "org.kde.plasma.digitalclock") bar = true;
    }
    if (dock) {
      p.location = "left";
      p.height = $DOCK_THICKNESS;
      p.hiding = "none";
      for (var j = 0; j < ids.length; j++) {
        var w = p.widgetById(ids[j]);
        if (w && w.type === "org.kde.mac.tahoe.liquid.icontasks") {
          w.currentConfigGroup = ["General"];
          w.writeConfig("launchers", pins);
        }
      }
    }
    if (bar) {
      var kv = null;
      for (var j = 0; j < ids.length; j++) {
        var w = p.widgetById(ids[j]);
        if (w && w.type === "org.kde.plasma.kvitals") kv = w;
      }
      if (!kv && p.addWidget) kv = p.addWidget("org.kde.plasma.kvitals");
      if (kv) {
        kv.currentConfigGroup = ["General"];
        kv.writeConfig("displayMode", "text");
        kv.writeConfig("fontFamily", "SF Pro Text 10pt");
        kv.writeConfig("iconSize", 14);
        kv.writeConfig("labelOpacity", 1);
        kv.writeConfig("pinnedMetrics", metrics);
        kv.writeConfig("separatorOpacity", 0);
        kv.writeConfig("showSeparators", false);
        kv.writeConfig("updateInterval", 3000);
        kv.currentConfigGroup = [];
        kv.writeConfig("popupHeight", 375);
        kv.writeConfig("popupWidth", 432);
        var kvId = kv.id;
        var order = [];
        var placed = false;
        for (var j = 0; j < ids.length; j++) {
          var w = p.widgetById(ids[j]);
          if (!w || w.id === kvId) continue;
          if (!placed && w.type === "org.kde.plasma.systemtray") {
            order.push(kvId);
            placed = true;
          }
          order.push(ids[j]);
        }
        if (!placed) order.unshift(kvId);
        p.currentConfigGroup = ["General"];
        p.writeConfig("AppletOrder", order.join(";"));
      }
    }
  }
})();
EOF
}

run_layout_script() {
    local script="$1" n=0
    for n in 1 2 3 4 5; do
        if "$QDBUS" org.kde.plasmashell /PlasmaShell \
             org.kde.PlasmaShell.evaluateScript "$script" >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
    done
    return 1
}

apply_layout() {
    ensure_qdbus
    printf '  [改动] 面板布局：dock 靠左常显 %spx，KVitals 置顶栏\n' "$DOCK_THICKNESS"
    local script
    script="$(layout_script)"
    run_layout_script "$script" || die "plasmashell 拒绝执行脚本，面板布局未变更"
    sleep 2
    run_layout_script "$script" || die "plasmashell 拒绝执行脚本，面板布局未变更"
}

cmd_apply() {
    printf '==> 重启 plasmashell，使主题生效\n'
    stop_plasmashell
    start_plasmashell

    printf '==> 安装 KVitals\n'
    kvitals_install

    printf '==> 重启 plasmashell，注册 plasmoid\n'
    stop_plasmashell
    start_plasmashell

    printf '==> 面板布局\n'
    apply_layout

    printf '==> 应用主题参数\n'
    apply_transparency
}

cmd_restore() {
    ensure_chezmoi

    local drift answer
    if ! drift="$(chezmoi -S "$DOTFILES" diff 2>&1)"; then
        die "chezmoi diff 执行失败"
    fi
    if [ -n "$drift" ]; then
        printf '==> 检测到漂移：本地配置和仓库快照不一致\n'
        printf '（每行截断至 200 字符，完整 diff 执行 chezmoi -S dotfiles diff 查看）\n'
        printf '%s\n' "$drift" | sed 's/^/  /' | cut -c1-200
        printf '继续将用仓库快照覆盖本地配置，建议先执行 make backup 固化 GUI 改动\n'
        printf '继续覆盖？(y/N) '
        read -r answer
        case "$answer" in
            y|Y|yes|YES) ;;
            *) die "已取消，本地配置未修改" ;;
        esac
    fi

    printf '==> 恢复配置快照\n'
    stop_plasmashell
    chezmoi -S "$DOTFILES" apply --force
    start_plasmashell
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
    printf '==> 快照已更新，仓库改动如下，请审阅后执行 git commit：\n'
    git -C "$ROOT" status --short -- dotfiles/
    git -C "$ROOT" diff -- dotfiles/
    printf '（无输出表示快照未变更，无需提交）\n'
}

case "${1:-}" in
    apply)   cmd_apply ;;
    kvitals) kvitals_install ;;
    restore) cmd_restore ;;
    backup)  cmd_backup ;;
    *) printf '用法：%s {apply|kvitals|restore|backup}\n' "${BASH_SOURCE[0]##*/}" >&2; exit 1 ;;
esac
