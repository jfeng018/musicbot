#!/bin/bash
source /musicbot/.env

LOG_DIR="/var/log/musicbot"
TEMP_FILE="/tmp/cleanup.tmp"
CLEANUP_LOG="$LOG_DIR/cleanup.log"

: > "$TEMP_FILE"
find "$LOG_DIR" -name "*.log" -mtime +${LOG_RETENTION_DAYS} -printf "%s %p\n" > "$TEMP_FILE"

total_files=$(wc -l < "$TEMP_FILE")
total_size=$(awk '{sum+=$1} END{print sum}' "$TEMP_FILE")
xargs -a <(awk '{print $2}' "$TEMP_FILE") rm -v

{
  echo "===== 清理报告 ====="
  echo "时间: $(date +'%F %T')"
  echo "保留天数: ${LOG_RETENTION_DAYS}"
  echo "清理文件: ${total_files}"
  echo "释放空间: $(numfmt --to=iec $total_size)"
} >> "$CLEANUP_LOG"

curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"*${SERVER_NAME} 日志清理* 🧹\n时间: $(date +'%F %T')\n保留天数: ${LOG_RETENTION_DAYS}\n清理文件: ${total_files}\n释放空间: $(numfmt --to=iec $total_size)\",\"parse_mode\":\"Markdown\"}" \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

rm -f "$TEMP_FILE"