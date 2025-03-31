#!/bin/bash
# 完全卸载脚本

set -e

INSTALL_DIR="/opt/musicbot"

confirm_uninstall() {
  read -p "确定要完全卸载吗？此操作不可逆！(y/N): " choice
  [[ "$choice" =~ [yY] ]] || exit 0
}

purge_files() {
  echo -e "${RED}▶ 删除所有相关文件...${NC}"
  systemctl stop musicbot 2>/dev/null || true
  systemctl disable musicbot 2>/dev/null || true
  rm -f /etc/systemd/system/musicbot.service
  rm -rf $INSTALL_DIR
  crontab -l | grep -v "musicbot" | crontab -
  echo -e "${GREEN}✅ 已清理所有文件${NC}"
}

main() {
  echo -e "${YELLOW}=== Navidrome 自动化管理卸载程序 ==="
  confirm_uninstall
  purge_files
  echo -e "${GREEN}卸载完成！${NC}"
}

main