REPO := $(CURDIR)/macos-tahoe-liquid-kde
REPO_URL := https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde.git
FLAGS := --light --no-firefox --no-plymouth --no-nautilus

.DEFAULT_GOAL := help
.PHONY: help setup check install update light dark auto uninstall backup restore

help:
	@echo ""
	@echo "  make setup      拉取主题仓库，安装 KVitals、chezmoi"
	@echo "  make check      装前体检，不改系统"
	@echo "  make install    安装主题（浅色，跳过 Firefox / 开机画面 / Nautilus）"
	@echo "  make update     更新主题，并刷新配置快照（git diff 审阅后提交）"
	@echo "  make light      切浅色"
	@echo "  make dark       切深色"
	@echo "  make auto       跟随时间自动切（06:00 浅 / 18:00 深）"
	@echo "  make uninstall  卸载主题"
	@echo "  make backup     备份当前设置（壁纸 / KVitals / dock）到 dotfiles/"
	@echo "  make restore    用 dotfiles/ 恢复设置到 ~/.config"
	@echo ""
	@echo "  install / update / restore 之后必须注销重新登录一次。"
	@echo "  GUI 改完 dock / KVitals / 壁纸后跑 make backup，再 git commit。"
	@echo ""

setup:
	@if [ -d "$(REPO)/.git" ]; then \
		echo "  [已有] 主题仓库 macos-tahoe-liquid-kde"; \
	elif [ -e "$(REPO)" ]; then \
		echo "  错误：$(REPO) 存在但不是 git 仓库，先删掉再重试：rm -rf $(REPO)"; \
		exit 1; \
	else \
		echo "  [拉取] macos-tahoe-liquid-kde"; \
		if git clone --depth 1 "$(REPO_URL)" "$(REPO)" 2>/dev/null; then \
			echo "  已拉取"; \
		elif curl -fsS --max-time 3 -x http://127.0.0.1:7897 -o /dev/null https://github.com; then \
			echo "  直连失败，走本机 7897 代理重试"; \
			rm -rf "$(REPO)"; \
			http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897 \
				git clone --depth 1 "$(REPO_URL)" "$(REPO)" || \
				{ rm -rf "$(REPO)"; echo "  克隆失败"; exit 1; }; \
			echo "  已拉取"; \
		else \
			echo "  克隆失败。终端里先跑 ssr 开代理，再重试"; \
			exit 1; \
		fi; \
	fi
	@if command -v chezmoi >/dev/null 2>&1; then \
		echo "  [已有] chezmoi"; \
	else \
		echo "  [安装] chezmoi"; \
		sudo dnf install -y chezmoi; \
	fi
	@./desktop.sh kvitals

check: setup
	@echo "==> 体检（不会修改任何东西）"
	@cd "$(REPO)" && sudo ./install $(FLAGS) --preflight

install: setup
	@echo "==> 安装主题 $(FLAGS)"
	@cd "$(REPO)" && sudo ./install $(FLAGS)
	@./desktop.sh apply
	@./desktop.sh restore
	@echo "==> 完成。现在注销重新登录。"

update: setup
	@echo "==> 拉取最新版"
	@cd "$(REPO)" && git checkout -- features.json src/offline/ 2>/dev/null || true
	@cd "$(REPO)" && git pull --ff-only
	@cd "$(REPO)" && sudo ./install $(FLAGS)
	@./desktop.sh apply
	@./desktop.sh backup
	@echo "==> 完成。注销重新登录；快照已刷新，git diff 审阅后提交。"

light:
	@command -v mac-tahoe-theme-switch >/dev/null || { echo "还没装，先 make install"; exit 1; }
	mac-tahoe-theme-switch light

dark:
	@command -v mac-tahoe-theme-switch >/dev/null || { echo "还没装，先 make install"; exit 1; }
	mac-tahoe-theme-switch dark

auto:
	@command -v mac-tahoe-theme-switch >/dev/null || { echo "还没装，先 make install"; exit 1; }
	mac-tahoe-theme-switch auto

uninstall: setup
	@echo "==> 卸载（和安装传同一组 FLAGS，保证对得上）"
	@cd "$(REPO)" && sudo ./uninstall $(FLAGS)
	@echo "==> 完成。注销重新登录。"
	@echo "    注意：grub、原面板布局、GTK4 配置这几项它还原不了。"

backup:
	@./desktop.sh backup

restore:
	@./desktop.sh restore
