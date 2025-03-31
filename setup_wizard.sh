#!/bin/bash
# 交互式配置向导

CONFIG_FILE="/opt/musicbot/.env"

# 输入验证函数
validate_input() {
  case $1 in
    "token")
      [[ "$2" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]] || { echo "Token格式错误！"; return 1; };;
    "chatid")
      [[ "$2" =~ ^-?[0-9]+$ ]] || { echo "Chat ID必须是数字！"; return 1; };;
    "days")
      [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -gt 0 ] || { echo "请输入有效天数！"; return 1; };;
  esac
}

# 收集配置
echo -e "\n=== Telegram 配置 ==="
while true; do
  read -p "请输入Bot Token: " token
  validate_input "token" "$token" && break
done

while true; do
  read -p "请输入Chat ID: " chatid
  validate_input "chatid" "$chatid" && break
done

echo -e "\n=== 系统配置 ==="
read -p "服务器名称 (默认: MyMusicServer): " servername
servername=${servername:-MyMusicServer}

while true; do
  read -p "日志保留天数 (默认: 3): " logdays
  logdays=${logdays:-3}
  validate_input "days" "$logdays" && break
done

read -p "不活跃周期 (如 6 months): " inactivity
inactivity=${inactivity:-6 months}

# 生成配置文件
cat > $CONFIG_FILE <<EOF
TELEGRAM_BOT_TOKEN="$token"
TELEGRAM_CHAT_ID="$chatid"
SERVER_NAME="$servername"
QUALITY_FORMAT_WEIGHT=40
QUALITY_BITRATE_WEIGHT=30
QUALITY_SIZE_WEIGHT=20
QUALITY_META_WEIGHT=10
INACTIVE_PERIOD="$inactivity"
LOG_RETENTION_DAYS=$logdays
EOF

echo -e "\n${GREEN}✅ 配置已保存到 $CONFIG_FILE${NC}"