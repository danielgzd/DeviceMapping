#!/usr/bin/env python3
# Copyright © 2026 gdd. All rights reserved.
"""同步 IPSW.me。保留历史设备；数据变化才递增版本，失败不覆盖文件。"""
import argparse
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def validate(rows):
    if not isinstance(rows, list) or not rows:
        raise ValueError('设备列表为空或格式错误')
    result = {}
    for row in rows:
        if not isinstance(row, dict) or any(not isinstance(row.get(k), str) or not row[k].strip() for k in ('identifier', 'name')):
            raise ValueError('设备标识或名称无效')
        if row['identifier'] in result:
            raise ValueError('设备标识重复')
        result[row['identifier']] = row
    return result

def generate(incoming, previous):
    devices = validate(previous['devices']) if previous else {}
    devices.update(validate(incoming))
    rows = sorted(devices.values(), key=lambda row: row['identifier'])
    old_rows = sorted(previous['devices'], key=lambda row: row['identifier']) if previous else []
    version = previous['version'] if previous else 0
    if isinstance(version, bool) or not isinstance(version, int) or version < 0:
        raise ValueError('历史版本无效')
    return {'version': version + (rows != old_rows), 'devices': rows}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', default='https://api.ipsw.me/v4/devices')
    parser.add_argument('--output', type=Path, default=ROOT / 'config/device-mapping.json')
    args = parser.parse_args()
    request = urllib.request.Request(args.source, headers={'User-Agent': 'DeviceMapping-Sync/1.0'})
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError('上游数据超过限制')
    previous = json.loads(args.output.read_text()) if args.output.exists() else None
    result = generate(json.loads(raw), previous)
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if len(encoded.encode()) > 2 * 1024 * 1024:
        raise ValueError('生成数据超过客户端限制')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix('.tmp')
    temporary.write_text(encoded)
    temporary.replace(args.output)
    print(f"配置版本 {result['version']}，设备数 {len(result['devices'])}")

if __name__ == '__main__':
    main()
