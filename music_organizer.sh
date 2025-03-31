#!/usr/bin/env python3
import os
import re
import hashlib
import json
import argparse
from pathlib import Path
from mutagen import File
from mutagen.easyid3 import EasyID3
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import requests
import subprocess

# 配置管理类
class ConfigManager:
    def __init__(self):
        self.config_path = Path.home() / ".music_organizer.conf"
        self.config = {}

    def load_config(self):
        if self.config_path.exists():
            with open(self.config_path, 'r') as f:
                self.config = json.load(f)

    def save_config(self):
        with open(self.config_path, 'w') as f:
            json.dump(self.config, f, indent=2)

    def get_param(self, key, prompt, is_secret=False):
        if key in self.config and input(f"{key}已存在，是否重新配置？(y/n) ").lower() != 'y':
            return self.config[key]

        value = input(prompt)
        if is_secret:
            value = value.strip()
        self.config[key] = value
        self.save_config()
        return value

# 音乐处理核心类
class MusicProcessor:
    def __init__(self, config):
        self.config = config
        self.processed_files = set()

    def _get_audio_quality(self, filepath):
        try:
            result = subprocess.check_output(
                f"ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 {filepath}",
                shell=True)
            return int(result.decode().strip())
        except Exception as e:
            print(f"获取音质失败: {str(e)}")
            return 0

    def _sanitize_path(self, text):
        return re.sub(r'[\\/*?:"<>|]', "_", text).strip()

    def process_file(self, src_path):
        if src_path in self.processed_files:
            return False

        try:
            audio = File(src_path, easy=True)
            if not audio:
                raise ValueError("不支持的文件格式")

            # 元数据提取
            meta = {
                'artist': audio.get('artist', ['Unknown Artist'])[0].split(';')[0].strip(),
                'album': audio.get('album', ['Unknown Album'])[0].strip(),
                'title': audio.get('title', [Path(src_path).stem])[0].strip(),
                'tracknumber': str(audio.get('tracknumber', ['0'])[0]).zfill(2),
                'bitrate': self._get_audio_quality(src_path)
            }

            # 路径构造
            dest_dir = Path(self.config['music_dir']) / self._sanitize_path(meta['artist'])
            dest_dir /= self._sanitize_path(meta['album'])
            dest_path = dest_dir / f"{meta['tracknumber']} - {self._sanitize_path(meta['title'])}{Path(src_path).suffix}"

            # 判重逻辑
            existing_files = [f for f in dest_dir.glob(f"*{Path(src_path).suffix}")
                            if f.stem.startswith(meta['tracknumber'])]
            if existing_files:
                existing_bitrate = max(self._get_audio_quality(f) for f in existing_files)
                if meta['bitrate'] <= existing_bitrate:
                    print(f"低质量重复: {dest_path}")
                    return False

            # 移动文件
            dest_dir.mkdir(parents=True, exist_ok=True)
            os.rename(src_path, dest_path)
            self.processed_files.add(src_path)
            return True

        except Exception as e:
            print(f"处理失败: {str(e)}")
            return False

# Telegram通知类
class TelegramNotifier:
    def __init__(self, token, chat_id):
        self.base_url = f"https://api.telegram.org/bot{token}/sendMessage"
        self.chat_id = chat_id

    def send(self, message):
        params = {
            'chat_id': self.chat_id,
            'text': message,
            'parse_mode': 'HTML'
        }
        requests.post(self.base_url, params=params)

# 监控处理类
class MusicHandler(FileSystemEventHandler):
    def __init__(self, processor, notifier):
        self.processor = processor
        self.notifier = notifier

    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith(('.mp3', '.flac', '.wav')):
            success = self.processor.process_file(event.src_path)
            if success:
                self.trigger_navidrome_scan()
                self.send_notification(event.src_path)

    def trigger_navidrome_scan(self):
        try:
            requests.post(
                f"http://localhost:{self.processor.config['navidrome_port']}/api/scan",
                headers={'X-ND-Auth': self.processor.config['navidrome_token']}
            )
        except Exception as e:
            print(f"扫描触发失败: {str(e)}")

    def send_notification(self, filename):
        message = f"🎵 新歌曲已整理:\n<code>{Path(filename).name}</code>"
        self.notifier.send(message)

if __name__ == "__main__":
    config = ConfigManager()
    config.load_config()

    required_params = [
        ('telegram_token', '请输入Telegram Bot Token: ', True),
        ('telegram_chat_id', '请输入Telegram Chat ID: ', True),
        ('navidrome_port', 'Navidrome端口（默认4533）: ', False),
        ('navidrome_token', 'Navidrome API Token: ', True),
        ('watch_dir', '监控目录（默认/root/SaveAny/downloads/upMusic）: ', False),
        ('music_dir', '目标目录（默认/root/SaveAny/downloads/music）: ', False)
    ]

    param_values = {}
    for param in required_params:
        key, prompt, is_secret = param
        param_values[key] = config.get_param(key, prompt, is_secret)

    # 初始化组件
    notifier = TelegramNotifier(param_values['telegram_token'], param_values['telegram_chat_id'])
    processor = MusicProcessor(param_values)
    event_handler = MusicHandler(processor, notifier)

    # 启动监控
    observer = Observer()
    observer.schedule(event_handler, param_values['watch_dir'], recursive=False)
    observer.start()
    print(f"开始监控目录: {param_values['watch_dir']}")

    try:
        while True:
            pass
    except KeyboardInterrupt:
        observer.stop()
    observer.join()