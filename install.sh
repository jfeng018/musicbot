#!/bin/bash
# Navidrome 自动化管理安装主菜单

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="/opt/musicbot"
CONFIG_FILE="$INSTALL_DIR/.env"

# 检查root权限
check_root() {
  [ "$EUID" -ne 0 ] && { echo -e "${RED}错误：请使用sudo运行此脚本${NC}"; exit 1; }
}

# 显示菜单
show_menu() {
  clear
  echo -e "${YELLOW}=== Navidrome 自动化管理 ===${NC}"
  echo "1. 全新安装"
  echo "2. 更新系统"
  echo "3. 卸载系统"
  echo "4. 退出"
  echo -n "请选择操作 [1-4]: "
}

# 安装依赖
install_deps() {
  echo -e "${GREEN}▶ 安装系统依赖...${NC}"
  apt update && apt install -y \
    python3 python3-pip \
    ffmpeg \
    sqlite3 \
    inotify-tools \
    parallel \
    jq \
    coreutils \
    fonts-wqy-zenhei
  pip3 install beets beets-copyartifacts beets-ftintitle beets-check
}

# 运行配置向导
run_wizard() {
  bash <(curl -sL https://raw.githubusercontent.com/jfeng018/musicbot/main/setup_wizard.sh)
}

# 部署核心组件
deploy_components() {
  echo -e "${GREEN}▶ 部署核心组件...${NC}"
  mkdir -p $INSTALL_DIR/{backups,scripts}

  # 下载核心脚本
  declare -a scripts=("musicbot.sh" "activity_check.sh" "cleanup_logs.sh")
  for script in "${scripts[@]}"; do
    curl -sL "https://raw.githubusercontent.com/jfeng018/musicbot/main/$script" \
      -o "$INSTALL_DIR/scripts/$script"
    chmod +x "$INSTALL_DIR/scripts/$script"
  done

  # 配置Systemd服务
  curl -sL "https://raw.githubusercontent.com/jfeng018/musicbot/main/musicbot.service" \
    -o "/etc/systemd/system/musicbot.service"

  # 配置Beets
  mkdir -p /etc/beets
  curl -sL "https://raw.githubusercontent.com/jfeng018/musicbot/main/config.yaml" \
    -o "/etc/beets/config.yaml"

  # 创建音乐目录
  mkdir -p /{music,upload} /var/log/musicbot
  chmod -R 775 /music /upload
}

# 配置定时任务
setup_cron() {
  (crontab -l 2>/dev/null; echo "0 3 * * 0 $INSTALL_DIR/scripts/activity_check.sh") | crontab -
  (crontab -l 2>/dev/null; echo "0 2 * * * $INSTALL_DIR/scripts/cleanup_logs.sh") | crontab -
}

# 安装完成
finish_install() {
  systemctl daemon-reload
  systemctl enable musicbot
  systemctl start musicbot
  echo -e "${GREEN}✅ 安装完成！${NC}"
  echo -e "控制命令: systemctl [start|stop|status] musicbot"
}

# 主安装流程
install() {
  check_root
  install_deps
  run_wizard
  deploy_components
  setup_cron
  finish_install
}

# 更新流程
update() {
  check_root
  echo -e "${GREEN}▶ 更新系统中...${NC}"
  systemctl stop musicbot
  rm -f $INSTALL_DIR/scripts/*.sh
  deploy_components
  systemctl start musicbot
  echo -e "${GREEN}✅ 更新完成！${NC}"
}

# 卸载流程
uninstall() {
  check_root
  echo -e "${RED}▶ 开始卸载...${NC}"
  systemctl stop musicbot
  systemctl disable musicbot
  rm -f /etc/systemd/system/musicbot.service
  rm -rf $INSTALL_DIR
  crontab -l | grep -v "musicbot" | crontab -
  echo -e "${GREEN}✅ 卸载完成！${NC}"
}

# 主菜单循环
while true; do
  show_menu
  read choice
  case $choice in
    1) install; break ;;
    2) update; break ;;
    3) uninstall; break ;;
    4) exit 0 ;;
    *) echo -e "${RED}无效选择！${NC}"; sleep 1 ;;
  esac
done