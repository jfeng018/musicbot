#!/bin/bash

set -e

# 支持的音频格式
SUPPORTED_FORMATS=("mp3" "flac" "wav" "aac" "ogg" "m4a")

# 配置文件路径
CONFIG_FILE="$HOME/.music_organizer_config"

# 读取或设置参数
read_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    read -p "请输入 Telegram Bot Token (留空使用历史配置): " INPUT_BOT_TOKEN
    TELEGRAM_BOT_TOKEN=${INPUT_BOT_TOKEN:-$TELEGRAM_BOT_TOKEN}

    read -p "请输入 Telegram Chat ID (留空使用历史配置): " INPUT_CHAT_ID
    TELEGRAM_CHAT_ID=${INPUT_CHAT_ID:-$TELEGRAM_CHAT_ID}

    read -p "请输入 Navidrome API 地址 (留空使用历史配置): " INPUT_NAVIDROME_API
    NAVIDROME_API=${INPUT_NAVIDROME_API:-$NAVIDROME_API}

    # 保存配置
    cat <<EOF > "$CONFIG_FILE"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
NAVIDROME_API="$NAVIDROME_API"
EOF
}

# 发送 Telegram 消息
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID&text=$message" >/dev/null
}

# 从 MusicBrainz 获取元数据
fetch_metadata() {
    local title="$1"
    local artist="$2"

    response=$(curl -s "https://musicbrainz.org/ws/2/recording/?query=recording:$title AND artist:$artist&fmt=json")
    new_title=$(echo "$response" | jq -r '.recordings[0].title')
    new_artist=$(echo "$response" | jq -r '.recordings[0].artist-credit[0].name')
    new_album=$(echo "$response" | jq -r '.recordings[0].releases[0].title')

    echo "$new_title|$new_artist|$new_album"
}

# 提取音频元数据
extract_metadata() {
    local file="$1"

    title=$(ffprobe -v quiet -print_format json -show_format "$file" | jq -r .format.tags.title)
    artist=$(ffprobe -v quiet -print_format json -show_format "$file" | jq -r .format.tags.artist)
    album=$(ffprobe -v quiet -print_format json -show_format "$file" | jq -r .format.tags.album)
    bitrate=$(ffprobe -v quiet -print_format json -show_format "$file" | jq -r .format.bit_rate)
    duration=$(ffprobe -v quiet -print_format json -show_format "$file" | jq -r .format.duration)

    # 处理未知元数据
    [ -z "$title" ] && title=$(basename "$file" | sed 's/ - .*//')
    [ -z "$artist" ] && artist="Unknown Artist"
    [ -z "$album" ] && album="Unknown Album"

    # 尝试从 MusicBrainz 补充元数据
    fetched_metadata=$(fetch_metadata "$title" "$artist")
    IFS="|" read -r new_title new_artist new_album <<< "$fetched_metadata"

    [ "$new_title" != "null" ] && title="$new_title"
    [ "$new_artist" != "null" ] && artist="$new_artist"
    [ "$new_album" != "null" ] && album="$new_album"

    echo "$title|$artist|$album|$bitrate|$duration"
}

# 更新音频文件的 ID3 标签
update_metadata() {
    local file="$1"
    local title="$2"
    local artist="$3"
    local album="$4"

    case "${file##*.}" in
        mp3)
            eyeD3 --title="$title" --artist="$artist" --album="$album" "$file" >/dev/null
            ;;
        flac)
            metaflac --set-tag="TITLE=$title" --set-tag="ARTIST=$artist" --set-tag="ALBUM=$album" "$file"
            ;;
        *)
            ffmpeg -i "$file" -metadata title="$title" -metadata artist="$artist" -metadata album="$album" -codec copy "${file}.tmp"
            mv "${file}.tmp" "$file"
            ;;
    esac
}

# 监听目录
watch_directory() {
    inotifywait -m -e close_write --format "%w%f" "/root/SaveAny/downloads/upMusic" | while read file; do
        metadata=$(extract_metadata "$file")
        IFS="|" read -r title artist album bitrate duration <<< "$metadata"

        # 移动到目标路径
        target_dir="/root/SaveAny/downloads/music/$artist/$album"
        mkdir -p "$target_dir"
        mv "$file" "$target_dir/$title.${file##*.}"

        # 更新元数据
        update_metadata "$target_dir/$title.${file##*.}" "$title" "$artist" "$album"

        # 触发 Navidrome 扫描
        curl -s "$NAVIDROME_API/api/v1/rescan" >/dev/null
        send_telegram "✅ 添加新歌曲: $title ($album) 🎵"
    done
}

# 执行
read_config
watch_directory