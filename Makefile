REPO := $(CURDIR)/macos-tahoe-liquid-kde
REPO_URL := https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde.git
FLAGS := --light --no-firefox --no-plymouth --no-nautilus

.DEFAULT_GOAL := help
.PHONY: help setup install theme-pull theme-install theme-update theme-check theme-uninstall \
        theme-light theme-dark theme-auto backup restore

help:
	@echo ""
	@echo "  make setup           系统配置（dnf、flatpak 源、开机项、zram 与 swap），不安装软件包"
	@echo "  make install         安装软件（基础工具、输入法、应用）"
	@echo ""
	@echo "  make theme-pull      拉取/更新主题仓库"
	@echo "  make theme-check     主题安装前检查，不修改系统"
	@echo "  make theme-install   安装主题（浅色，跳过 Firefox / 开机画面 / Nautilus）"
	@echo "  make theme-update    更新主题"
	@echo "  make theme-uninstall 卸载主题"
	@echo "  make theme-light     切换浅色"
	@echo "  make theme-dark      切换深色"
	@echo "  make theme-auto      按时间自动切换（06:00 浅色 / 18:00 深色）"
	@echo ""
	@echo "  make backup          备份设置（桌面布局 / 输入法 / 电源）到 dotfiles/"
	@echo "  make restore         从 dotfiles/ 恢复设置到 ~/.config"
	@echo ""
	@echo "  换机顺序：setup → install → theme-pull → theme-install → restore。"
	@echo "  theme-install / theme-update / restore 之后必须注销并重新登录。"
	@echo "  通过 GUI 修改 dock / KVitals / 壁纸 / 输入法 / 电源后执行 make backup，再 git commit。"
	@echo ""

setup:
	@./setup.sh

install:
	@./packages.sh

theme-pull:
	@if [ -d "$(REPO)/.git" ]; then \
		echo "  [更新] 拉取主题仓库"; \
		cd "$(REPO)" && git checkout -- features.json src/offline/ 2>/dev/null || true; \
		git -C "$(REPO)" pull --ff-only || { echo "  [失败] 拉取主题仓库"; exit 1; }; \
	elif [ -e "$(REPO)" ]; then \
		echo "  错误：$(REPO) 存在但不是 git 仓库，请删除后重试：rm -rf $(REPO)"; \
		exit 1; \
	else \
		echo "  [拉取] 主题仓库 macos-tahoe-liquid-kde"; \
		git clone --depth 1 "$(REPO_URL)" "$(REPO)" || { rm -rf "$(REPO)"; echo "  [失败] 拉取主题仓库"; exit 1; }; \
		echo "  [完成] 拉取主题仓库"; \
	fi

theme-check:
	@[ -d "$(REPO)/.git" ] || { echo "  主题仓库未拉取，请先执行 make theme-pull"; exit 1; }
	@echo "==> 安装前检查（不修改系统）"
	@cd "$(REPO)" && sudo ./install $(FLAGS) --preflight

theme-install:
	@[ -d "$(REPO)/.git" ] || { echo "  主题仓库未拉取，请先执行 make theme-pull"; exit 1; }
	@echo "==> 安装主题 $(FLAGS)"
	@cd "$(REPO)" && sudo ./install $(FLAGS)
	@./desktop.sh apply
	@echo "==> 完成，请注销并重新登录。"
	@echo "    个人设置（dock 固定的应用、KVitals 指标、壁纸）通过 make restore 恢复。"

theme-update:
	@[ -d "$(REPO)/.git" ] || { echo "  主题仓库未拉取，请先执行 make theme-pull"; exit 1; }
	@echo "==> 重新安装主题 $(FLAGS)"
	@cd "$(REPO)" && sudo ./install $(FLAGS)
	@./desktop.sh apply
	@echo "==> 完成，请注销并重新登录。"
	@echo "    如需固化当前设置，执行 make backup。"

theme-uninstall:
	@[ -d "$(REPO)/.git" ] || { echo "  主题仓库未拉取，请先执行 make theme-pull"; exit 1; }
	@echo "==> 卸载主题（与安装使用相同的 FLAGS）"
	@cd "$(REPO)" && sudo ./uninstall $(FLAGS)
	@echo "==> 完成，请注销并重新登录。"
	@echo "    注意：grub、原面板布局、GTK4 配置无法还原。"

theme-light:
	@command -v mac-tahoe-theme-switch >/dev/null || { echo "  主题未安装，请先执行 make theme-install"; exit 1; }
	mac-tahoe-theme-switch light

theme-dark:
	@command -v mac-tahoe-theme-switch >/dev/null || { echo "  主题未安装，请先执行 make theme-install"; exit 1; }
	mac-tahoe-theme-switch dark

theme-auto:
	@command -v mac-tahoe-theme-switch >/dev/null || { echo "  主题未安装，请先执行 make theme-install"; exit 1; }
	mac-tahoe-theme-switch auto

backup:
	@./desktop.sh backup

restore:
	@./desktop.sh restore
