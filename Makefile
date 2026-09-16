REPO := $(CURDIR)/macos-tahoe-liquid-kde
REPO_URL := https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde.git
FLAGS := --light --no-firefox --no-plymouth --no-nautilus

TARBALL_URL := https://github.com/matinlotfali/KDE-Rounded-Corners/archive/refs/tags/v0.9.0.tar.gz
TARBALL_SHA := 4acaf2dad31a22cbfa009bdce836b969177996527237eb8c62c8393e03622c5f
TARBALL     := $(REPO)/build/online/kde-rounded-corners/KDE-Rounded-Corners-0.9.0.tar.gz

.DEFAULT_GOAL := help
.PHONY: help clone prefetch check install update light dark auto uninstall personal

help:
	@echo ""
	@echo "  make check       装之前先体检，不改系统"
	@echo "  make install     安装（浅色，跳过 Firefox / 开机画面 / Nautilus）"
	@echo "                   上游仓库没拉过会自动拉，拉过就直接用"
	@echo "  make update      拉最新版并重装"
	@echo ""
	@echo "  make personal    应用个人配置"
	@echo "                   desktop-personal/ 里写着的键才写过去，没写的一律不碰"
	@echo "                   要加什么，从 ~/.config/ 里同名文件拷段和键过来"
	@echo "                   面板相关的（dock 靠左、厚度、钉的应用、顶栏 KVitals）"
	@echo "                   改 desktop.sh 顶部的变量"
	@echo ""
	@echo "  make light       切浅色"
	@echo "  make dark        切深色"
	@echo "  make auto        跟随时间自动切（06:00 浅 / 18:00 深）"
	@echo "  make uninstall   卸载"
	@echo ""
	@echo "  装完必须注销重新登录一次。"
	@echo ""

clone:
	@if [ -d "$(REPO)/.git" ]; then \
		echo "  [已有] 上游仓库 macos-tahoe-liquid-kde"; \
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
			echo "  克隆失败。终端里先跑 ssr 开代理，再敲 make install"; \
			exit 1; \
		fi; \
	fi

prefetch: clone
	@if [ -f "$(TARBALL)" ] && \
	   [ "$$(sha256sum "$(TARBALL)" | cut -d' ' -f1)" = "$(TARBALL_SHA)" ]; then \
		echo "  [缓存命中] KDE-Rounded-Corners v0.9.0"; \
	else \
		mkdir -p "$$(dirname "$(TARBALL)")"; \
		echo "  [下载] KDE-Rounded-Corners v0.9.0"; \
		curl -fL --retry 5 -o "$(TARBALL).part" "$(TARBALL_URL)" || \
			{ rm -f "$(TARBALL).part"; echo "  下载失败"; exit 1; }; \
		echo "$(TARBALL_SHA)  $(TARBALL).part" | sha256sum -c - >/dev/null || \
			{ rm -f "$(TARBALL).part"; echo "  校验失败，已丢弃"; exit 1; }; \
		mv "$(TARBALL).part" "$(TARBALL)"; \
		echo "  已下载并校验"; \
	fi

check: clone
	@echo "==> 体检（不会修改任何东西）"
	@cd "$(REPO)" && sudo ./install $(FLAGS) --preflight

install: prefetch
	@echo "==> 安装 $(FLAGS)"
	@cd "$(REPO)" && sudo ./install $(FLAGS)
	@echo ""
	@echo "==> 重启 plasmashell，让主题生效"
	@./desktop.sh restart
	@echo ""
	@echo "==> 装 KVitals"
	@./desktop.sh kvitals
	@echo "==> 重启 plasmashell，让 plasmoid 注册"
	@./desktop.sh restart
	@echo ""
	@./desktop.sh personal
	@echo ""
	@echo "==> 完成。现在注销重新登录。"

update: clone
	@echo "==> 拉取最新版"
	@cd "$(REPO)" && git checkout -- features.json 2>/dev/null || true
	@cd "$(REPO)" && git checkout -- src/offline/ 2>/dev/null || true
	@cd "$(REPO)" && git pull --ff-only
	@$(MAKE) --no-print-directory install

personal:
	@./desktop.sh personal

light:
	@command -v mac-tahoe-theme-switch >/dev/null || { echo "还没装，先 make install"; exit 1; }
	mac-tahoe-theme-switch light

dark:
	@command -v mac-tahoe-theme-switch >/dev/null || { echo "还没装，先 make install"; exit 1; }
	mac-tahoe-theme-switch dark

auto:
	@command -v mac-tahoe-theme-switch >/dev/null || { echo "还没装，先 make install"; exit 1; }
	mac-tahoe-theme-switch auto

uninstall: clone
	@echo "==> 卸载（会和安装时传同一组 FLAGS，保证对得上）"
	@cd "$(REPO)" && sudo ./uninstall $(FLAGS)
	@echo ""
	@echo "==> 完成。注销重新登录。"
	@echo "    注意：grub、原面板布局、GTK4 配置这几项它还原不了。"
