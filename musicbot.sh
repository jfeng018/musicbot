#!/bin/bash
source /musicbot/.env

LOG_FILE="/var/log/musicbot/processor.log"
exec > >(tee -a "$LOG_FILE") 2>&1

notify() {
  local action="$1" file="$2" details="$3" emoji="🎵"
  case $action in
    "IMPORT_SUCCESS") emoji="✅";; "IMPORT_FAIL") emoji="❌";;
    "QUALITY_REPLACE")emoji="🔄";; "QUALITY_SKIP")emoji="⏭️";;
    "ACTIVITY_ALERT")emoji="📉";; "CLEANUP_REPORT")emoji="🧹";;
  esac

  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"${emoji} *${SERVER_NAME} ${action}*\n\`${file}\`\n${details}\",\"parse_mode\":\"Markdown\"}" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
}

quality_score() {
  local file="$1" format bitrate filesize
  format=$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=nw=1:nk=1 "$file")
  bitrate=$(ffprobe -v error -select_streams a -show_entries format=bit_rate -of default=nw=1:nk=1 "$file")
  filesize=$(stat -c%s "$file")

  declare -A format_scores=([flac]=100 [alac]=90 [wav]=80 [aac]=70 [mp3]=60)
  local f_score=${format_scores[${format,,}]:-50}
  local br_score=$(( (bitrate * 100) / 1000000 ))
  (( br_score > 100 )) && br_score=100
  local sz_score=$(( (filesize * 100) / 25000000 ))
  (( sz_score > 100 )) && sz_score=100

  local meta_score=0
  beet info "$file" | grep -q "Cover: yes" && ((meta_score+=5))
  beet info "$file" | grep -q "Lyrics: yes" && ((meta_score+=5))

  echo $((
    f_score*QUALITY_FORMAT_WEIGHT/100 +
    br_score*QUALITY_BITRATE_WEIGHT/100 +
    sz_score*QUALITY_SIZE_WEIGHT/100 +
    meta_score*QUALITY_META_WEIGHT/100
  ))
}

process_file() {
  local file="$1" existing metadata error_msg
  existing=$(beet list path:"$file" duplicates -f '$path')

  if [[ -n "$existing" ]]; then
    old_score=$(quality_score "$existing")
    new_score=$(quality_score "$file")

    if (( new_score > old_score )); then
      backup_dir="/music/backups/$(date +%Y%m%d)"
      mkdir -p "$backup_dir"
      mv "$existing" "$backup_dir/"
      mv "$file" "${existing%/*}/"
      notify "QUALITY_REPLACE" "$(basename "$file")" "新质量:${new_score} 旧质量:${old_score}"
    else
      rm "$file"
      notify "QUALITY_SKIP" "$(basename "$file")" "当前版本更优:${old_score}"
    fi
    return $?
  fi

  if beet import -q --flat "$file"; then
    metadata=$(beet info "$file" | jq -r '[.artist, .album, .title] | join(" - ")')
    notify "IMPORT_SUCCESS" "$(basename "$file")" "$metadata"
    rm "$file"
  else
    error_msg=$(tail -n1 /var/log/musicbot/beets.log | sed 's/"/“/g')
    notify "IMPORT_FAIL" "$(basename "$file")" "$error_msg"
    mv "$file" "/music/failed/"
  fi
}

inotifywait -m -r -e create,moved_to --format '%w%f' /upload | \
while read -r file; do
  [[ "$file" =~ \.(mp3|flac|m4a|ogg)$ ]] || continue
  process_file "$file" &
done