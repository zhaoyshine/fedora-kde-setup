#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$ROOT/macos-tahoe-liquid-kde"
DOTFILES="$ROOT/dotfiles"
CONFIG_DIR="$HOME/.config"

KV_ID="org.kde.plasma.kvitals"
KV_VER="v3.1.2"
KV_URL="https://github.com/yassine20011/kvitals/releases/download/$KV_VER/$KV_ID-$KV_VER.plasmoid"
KV_SHA="14126ce5ff447236566bee529db0850495d3bfa4c0b520c74c553d347364abac"
KV_PKG="$ROOT/kvitals/$KV_ID-$KV_VER.plasmoid"
KV_DEST="$HOME/.local/share/plasma/plasmoids/$KV_ID"

# 布局默认值，只影响 install / update 时的 apply
OPACITY=90
DOCK_OPACITY=12
DOCK_THICKNESS=64
DOCK_PINS="applications:systemsettings.desktop,applications:org.kde.discover.desktop,preferred://filemanager,applications:org.localsend.localsend_app.desktop,preferred://browser,applications:com.mitchellh.ghostty.desktop,applications:com.visualstudio.code.desktop,applications:zcode.desktop"
KV_METRICS="cpu/temp,gpu:gpu0/temp,disk:nvme0n1/temp,net/up,net/down"

QDBUS=""

die() { printf '错误：%s\n' "$1" >&2; exit 1; }

ensure_chezmoi() {
    command -v chezmoi >/dev/null || die "找不到 chezmoi，先装：sudo dnf install chezmoi"
    [ -d "$DOTFILES" ] || die "找不到 $DOTFILES，仓库是不是不完整？"
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
    die "找不到 qdbus，先装 qt6-qttools"
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
    printf '  面板归位：dock 靠左常显 %spx，KVitals 进顶栏\n' "$DOCK_THICKNESS"
    local script
    script="$(layout_script)"
    run_layout_script "$script" || die "plasmashell 不接受脚本，面板没动"
    sleep 2
    run_layout_script "$script" || die "plasmashell 不接受脚本，面板没动"
}

cmd_apply() {
    printf '==> 重启 plasmashell，让主题生效\n'
    stop_plasmashell
    start_plasmashell

    printf '==> 装 KVitals\n'
    kvitals_install

    printf '==> 重启 plasmashell，让 plasmoid 注册\n'
    stop_plasmashell
    start_plasmashell

    printf '==> 面板布局\n'
    apply_layout

    printf '==> 主题调参\n'
    apply_transparency
}

cmd_restore() {
    ensure_chezmoi

    local drift answer
    drift="$(chezmoi -S "$DOTFILES" diff 2>&1)" || die "chezmoi diff 失败"
    if [ -n "$drift" ]; then
        printf '==> 检测到漂移：本地配置和仓库快照不一致\n'
        printf '（每行截到 200 字符，完整 diff 用 chezmoi -S dotfiles diff 看）\n'
        printf '%s\n' "$drift" | sed 's/^/  /' | cut -c1-200
        printf '继续会用仓库快照覆盖本地配置。建议先 make backup 把 GUI 改动固化进仓库。\n'
        printf '继续覆盖？(y/N) '
        read -r answer
        case "$answer" in
            y|Y|yes|YES) ;;
            *) die "已取消，本地配置未动" ;;
        esac
    fi

    printf '==> 恢复配置快照\n'
    stop_plasmashell
    chezmoi -S "$DOTFILES" apply --force
    start_plasmashell
}

cmd_backup() {
    ensure_chezmoi
    local src="$CONFIG_DIR/plasma-org.kde.plasma.desktop-appletsrc"
    [ -f "$src" ] || die "$src 不存在"
    printf '==> 把 live 配置回写进仓库快照\n'
    chezmoi -S "$DOTFILES" add "$src"
    printf '==> 快照已刷新。仓库里的改动如下，审阅后 git commit：\n'
    git -C "$ROOT" status --short -- dotfiles/
    git -C "$ROOT" diff -- dotfiles/
    printf '（上面没输出的话说明快照没变，不用提交）\n'
}

case "${1:-}" in
    apply)   cmd_apply ;;
    kvitals) kvitals_install ;;
    restore) cmd_restore ;;
    backup)  cmd_backup ;;
    *) printf '用法：%s {apply|kvitals|restore|backup}\n' "${BASH_SOURCE[0]##*/}" >&2; exit 1 ;;
esac
