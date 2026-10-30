#!/usr/bin/env python3
# Copyright © 2026 gdd. Licensed under the MIT License.
"""通过 Actions Secrets 发送 Telegram 通知，不输出令牌或请求地址。"""
import json
import os
import sys
import urllib.request


def main():
    token = os.environ.get('TELEGRAM_BOT_TOKEN', '')
    chat_id = os.environ.get('TELEGRAM_CHAT_ID', '')
    if not token or not chat_id:
        print('Telegram Secrets 未配置，跳过通知。')
        return
    status = os.environ.get('SYNC_STATUS', 'failure')
    changed = os.environ.get('CONFIG_CHANGED') == 'true'
    if status == 'success' and not changed:
        print('配置没有变化，不发送通知。')
        return
    repository = os.environ.get('GITHUB_REPOSITORY', '')
    run_id = os.environ.get('GITHUB_RUN_ID', '')
    message = '设备映射配置已更新' if status == 'success' else '设备映射同步失败，请检查运行记录'
    text = f'{message}\n仓库：{repository}\nhttps://github.com/{repository}/actions/runs/{run_id}'
    body = json.dumps({'chat_id': chat_id, 'text': text, 'disable_web_page_preview': True}).encode()
    request = urllib.request.Request(
        f'https://api.telegram.org/bot{token}/sendMessage',
        data=body, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.load(response)
        if not result.get('ok'):
            raise ValueError('Telegram rejected request')
    except Exception:
        # 异常可能携带含令牌的 URL，不输出异常对象。
        print('Telegram 推送失败，请检查 Bot Token、Chat ID 和会话权限。', file=sys.stderr)
        sys.exit(1)
    print('Telegram 推送成功。')


if __name__ == '__main__':
    main()
