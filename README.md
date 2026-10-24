# fedora-kde-setup

Fedora KDE 装机包含三个步骤：系统配置、软件安装、安装 `macos-tahoe-liquid-kde` 主题。
个人设置与系统配置由 [chezmoi](https://www.chezmoi.io/) 以快照方式管理，快照源分别为 `dotfiles/` 与 `system/`。

换新机器的执行顺序：`make setup` → `make install` → `make theme-pull` → `make theme-install` → `make restore`。
每个 target 职责单一：setup 做一次性系统配置，install 安装软件，theme-* 管理主题，backup/restore 管理系统与个人设置快照。

## 命令

```sh
make setup           # 一次性系统配置，不安装软件包：dnf 调优、flatpak 仅保留 flathub、禁用 NetworkManager-wait-online 开机项
make install         # 安装软件：基础工具、fcitx5、LACT、Chrome、flatpak 应用

make theme-pull      # 拉取/更新主题仓库
make theme-check     # 主题安装前检查，不修改系统
make theme-install   # 安装主题（浅色，跳过 Firefox / 开机画面 / Nautilus）
make theme-update    # 更新主题
make theme-uninstall # 卸载主题
make theme-light     # 切换浅色
make theme-dark      # 切换深色
make theme-auto      # 按时间自动切换（06:00 浅色 / 18:00 深色）

make backup          # 备份设置到 dotfiles/、system/ 与 swap.conf
make restore         # 用 dotfiles/ 与 system/ 恢复设置
```

## 快照管理的文件

| 文件 | 内容 |
|---|---|
| `~/.config/plasma-org.kde.plasma.desktop-appletsrc` | dock 位置与厚度、固定的应用、KVitals 参数、壁纸 |
| `~/.config/plasmashellrc` | 面板厚度、floating 与可见性 |
| `~/.config/plasmarc` | Plasma 主题与壁纸列表 |
| `~/.config/kdeglobals` | 字体、颜色、图标与单击行为 |
| `~/.config/kglobalshortcutsrc` | 全局快捷键 |
| `~/.config/kscreenlockerrc` | 屏幕锁定超时 |
| `~/.config/fcitx5/config` | 输入法热键与行为 |
| `~/.config/fcitx5/profile` | 输入法组与顺序 |
| `~/.config/environment.d/fcitx5.conf` | `XMODIFIERS`（XWayland 程序依赖它获取输入法） |
| `~/.config/ghostty/config.ghostty` | Ghostty 键位绑定、初始命令、scrollback |
| `~/.config/kxkbrc` | 键盘布局与修饰键交换（左右 Ctrl/Alt） |
| `~/.config/kwinrc` | 窗口管理：虚拟桌面、平铺布局、窗口行为、效果开关、标题栏按钮 |
| `~/.config/kwinrulesrc` | 窗口规则 |
| `~/.config/powerdevilrc` | 屏幕变暗、息屏、休眠策略 |
| `/etc/udev/rules.d/` | 本地 udev 规则：A770 110W 功耗上限、移除 HDMI 音频 |
| `/etc/sysctl.d/99-swap.conf` | `vm.swappiness` |
| `/etc/systemd/zram-generator.conf` | zram 开关（空文件即关闭） |
| `swap.conf` | swapfile 路径、大小与 `/etc/fstab` 条目，由 `backup` 从当前系统提取 |

- `theme-install` / `theme-update` 附带安装 KWin 插件（KVitals、MouseTiler），从 GitHub 下载固定版本并校验 sha256，无法访问时先启动 `ssr` 代理。
- `theme-install` / `theme-update` / `restore` 之后必须注销并重新登录。
- 通过 GUI 或手工修改 dock / KVitals / 壁纸 / 快捷键 / 输入法 / 窗口管理 / 电源 / udev 规则 / swap 后，执行 `make backup` 再 `git commit`。
- 恢复到历史版本：`git checkout <commit> -- dotfiles/ system/ swap.conf` 再 `make restore`。
- 系统配置快照由 sudo 写回 `/etc`，`restore` 会重载 udev、sysctl 与 systemd。
- `backup` 从 `/etc/fstab` 提取 swapfile 条目并把路径、大小写入 `swap.conf`；`restore` 据此重建 swapfile 并确保 `/etc/fstab` 含对应条目，`/etc/fstab` 的其余条目属于目标机，不纳入快照。
- `restore` 会把 Plasma 布局绑定到当前活动，并把 Plasma 壁纸与 Ghostty 配置中的旧主目录改为当前 `$HOME`；多显示器布局仍按源机记录，跨机器恢复后检查面板位置。
- 显示器布局（`kwinoutputconfig.json` 与 kscreen 配置）与硬件绑定，不纳入快照。
- `restore` 覆盖前会把当前配置快照到 `~/.local/state/fedora-kde-setup/pre-restore-<时间>/`。

## 前置条件

- 已安装 Fedora KDE 桌面，可正常登录
- 无法访问 GitHub 时先启动 `ssr` 代理
- 不使用国内镜像源，dnf / flatpak / pip / npm 均使用官方源
