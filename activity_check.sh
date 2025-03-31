#!/bin/bash
source /musicbot/.env

DB_PATH="/var/lib/navidrome/navidrome.db"
REPORT_CSV="/tmp/activity_report.csv"

sqlite3 -csv "$DB_PATH" <<SQL > "$REPORT_CSV"
SELECT
    mf.path,
    MAX(ph.play_date) AS last_played,
    COUNT(ph.id) AS play_count
FROM media_file mf
LEFT JOIN play_history ph ON mf.id = ph.media_file_id
GROUP BY mf.id
HAVING last_played < date('now', '-${INACTIVE_PERIOD}') OR last_played IS NULL
ORDER BY last_played ASC
LIMIT 50;
SQL

if [[ -s "$REPORT_CSV" ]]; then
  message="*${SERVER_NAME} 活跃度报告* 📉 周期: ${INACTIVE_PERIOD}\n"
  while IFS=, read -r path last_played play_count; do
    [[ "$path" == "path" ]] && continue
    song=$(basename "${path%.*}" | sed 's/_/ /g')
    last_played=${last_played:-从未播放}
    message+="\n• ${song}\n  最后播放: ${last_played} 次数: ${play_count}"
  done < "$REPORT_CSV"

  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"$message\",\"parse_mode\":\"Markdown\"}" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
fi

rm -f "$REPORT_CSV"