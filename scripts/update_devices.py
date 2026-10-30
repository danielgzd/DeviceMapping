#!/usr/bin/env python3
# Copyright © 2026 gdd. Licensed under the MIT License.
"""同步 IPSW.me。保留历史设备；每次成功构建递增版本，失败不覆盖文件。"""
from datetime import datetime
from zoneinfo import ZoneInfo
import argparse
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

CATEGORIES = {
    'iphone': ('iPhone',), 'ipad': ('iPad',), 'ipod': ('iPod',),
    'mac': ('Mac', 'iMac', 'VirtualMac', 'ADP'),
    'watch': ('Watch',), 'appletv': ('AppleTV',),
    'homepod': ('AudioAccessory',), 'vision': ('RealityDevice',),
    'ibridge': ('iBridge',),
}

def category(identifier):
    if identifier in ('arm64', 'i386', 'x86_64'):
        return 'simulator'
    return next((name for name, prefixes in CATEGORIES.items() if identifier.startswith(prefixes)), 'other')

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

def generate(incoming, previous, build_time=None):
    devices = validate(previous['devices']) if previous else {}
    devices.update(validate(incoming))
    rows = sorted(devices.values(), key=lambda row: row['identifier'])
    version = previous['version'] if previous else 0
    if isinstance(version, bool) or not isinstance(version, int) or version < 0:
        raise ValueError('历史版本无效')
    return {'version': version + 1, 'buildTime': build_time or datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(timespec='seconds'), 'devices': rows}

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
    build_time = datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds")
    result = generate(json.loads(raw), previous, build_time)
    outputs = {args.output: result}
    # 分类依据硬件标识，不依赖可能重名或变化的设备名称。
    for name in [*CATEGORIES, 'simulator', 'other', 'ios']:
        path = args.output.parent / f'{name}.json'
        rows = [row for row in result['devices'] if (
            category(row['identifier']) in ('iphone', 'ipad', 'ipod') if name == 'ios'
            else category(row['identifier']) == name
        )]
        # 没有记录的类别不发布空配置，客户端拒绝空设备列表。
        if not rows:
            continue
        old = json.loads(path.read_text()) if path.exists() else None
        # 各分类独立递增；首次沿用全量版本，避免由全量地址切换时发生版本回退。
        outputs[path] = {'version': old['version'] + 1, 'buildTime': build_time, 'devices': rows} if old else {'version': result['version'], 'buildTime': build_time, 'devices': rows}
        validate(rows)
    # 全部校验后再落盘，避免校验失败时发布部分文件。
    encoded_outputs = {}
    for path, config in outputs.items():
        encoded = json.dumps(config, ensure_ascii=False, indent=2) + '\n'
        if len(encoded.encode()) > 2 * 1024 * 1024:
            raise ValueError('生成数据超过客户端限制')
        encoded_outputs[path] = encoded
    for path, encoded in encoded_outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix('.tmp')
        temporary.write_text(encoded)
        temporary.replace(path)
        config = outputs[path]
        print(f"{path.name}: 版本 {config['version']}，设备数 {len(config['devices'])}")

if __name__ == '__main__':
    main()
