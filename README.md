# fedora-kde-setup

Fedora KDE 一键装 macos-tahoe-liquid-kde 主题 + KVitals；个人设置用
[chezmoi](https://www.chezmoi.io/) 快照管理（`dotfiles/` 即快照源）。

纳管文件：`~/.config/plasma-org.kde.plasma.desktop-appletsrc`
（dock 位置/厚度、钉住的应用、KVitals 参数、壁纸，全在这一个文件里）。

## 命令

```sh
make setup      # 拉取主题仓库，安装 KVitals、chezmoi
make check      # 装前体检，不改系统
make install    # 安装主题 + KVitals，恢复设置
make update     # 更新主题，刷新快照（git diff 审阅后提交）
make light      # 切浅色
make dark       # 切深色
make auto       # 跟随时间自动切（06:00 浅 / 18:00 深）
make uninstall  # 卸载主题
make backup     # 备份当前设置到 dotfiles/（GUI 改完后跑）
make restore    # 用 dotfiles/ 恢复设置
```

- install / update / restore 之后必须注销重新登录一次。
- GUI 改完 dock / KVitals / 壁纸：`make backup` 然后 `git commit`。
- 恢复到历史版本：`git checkout <commit> -- dotfiles/` 再 `make restore`。
- 布局默认值（dock 厚度、钉住的应用、KVitals 指标）改 `desktop.sh` 顶部变量，只影响 install / update。
- 快照是单机的（containment ID 机器相关），别跨机器复用。

## 前置

- Fedora KDE，能进桌面
- GitHub 走不通就先跑 `ssr` 开代理（clone 会自动回退 7897 代理）
