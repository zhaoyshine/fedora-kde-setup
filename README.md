# fedora-kde-setup

Fedora KDE 装机包含三个步骤：系统配置、软件安装、安装 `macos-tahoe-liquid-kde` 主题。
个人设置由 [chezmoi](https://www.chezmoi.io/) 以快照方式管理，快照源为 `dotfiles/`。

换新机器的执行顺序：`make setup` → `make install` → `make theme-pull` → `make theme-install` → `make restore`。
每个 target 职责单一：setup 配置系统，install 安装软件，theme-* 管理主题，backup/restore 管理个人设置快照。

## 命令

```sh
make setup           # 系统配置，不安装软件包：dnf 调优、flatpak 仅保留 flathub、禁用 NetworkManager-wait-online 开机项
make install         # 安装软件：基础工具、fcitx5、LACT、Chrome、flatpak 应用

make theme-pull      # 拉取/更新主题仓库
make theme-check     # 主题安装前检查，不修改系统
make theme-install   # 安装主题（浅色，跳过 Firefox / 开机画面 / Nautilus）
make theme-update    # 更新主题
make theme-uninstall # 卸载主题
make theme-light     # 切换浅色
make theme-dark      # 切换深色
make theme-auto      # 按时间自动切换（06:00 浅色 / 18:00 深色）

make backup          # 备份设置到 dotfiles/
make restore         # 用 dotfiles/ 恢复设置
```

## 快照管理的文件

| 文件 | 内容 |
|---|---|
| `~/.config/plasma-org.kde.plasma.desktop-appletsrc` | dock 位置与厚度、固定的应用、KVitals 参数、壁纸 |
| `~/.config/fcitx5/config` | 输入法热键与行为 |
| `~/.config/fcitx5/profile` | 输入法组与顺序 |
| `~/.config/environment.d/fcitx5.conf` | `XMODIFIERS`（XWayland 程序依赖它获取输入法） |
| `~/.config/ghostty/config.ghostty` | Ghostty 键位绑定、初始命令、scrollback |
| `~/.config/kxkbrc` | 键盘布局与修饰键交换（左右 Ctrl/Alt） |
| `~/.config/powerdevilrc` | 屏幕变暗、息屏、休眠策略 |

- `theme-install` / `theme-update` / `restore` 之后必须注销并重新登录。
- 通过 GUI 修改 dock / KVitals / 壁纸 / 输入法 / 电源后，执行 `make backup` 再 `git commit`。
- 恢复到历史版本：`git checkout <commit> -- dotfiles/` 再 `make restore`。
- 布局默认值（dock 厚度、固定的应用、KVitals 指标）修改 `desktop.sh` 顶部变量，仅影响 `theme-install` / `theme-update`。
- 快照与单机绑定（containment ID 与机器相关），勿跨机器复用。

## 前置条件

- 已安装 Fedora KDE 桌面，可正常登录
- 无法访问 GitHub 时先启动 `ssr` 代理
- 不使用国内镜像源，dnf / flatpak / pip / npm 均使用官方源
