# DeviceMapping

Copyright © 2026 gdd. All rights reserved.

iOS 15+ 设备名称查询工具与自动更新配置。工具支持 iPhone、iPad 等 IPSW.me 收录设备；演示 App 最低 iOS 16。

## 两份配置

- `config/device-mapping.json`：GitHub Actions 每天生成，作为远端配置。
- `DeviceMapping/DeviceInfo/device-mapping.json`：随 App 打包的本地保底快照，定时任务不会修改它。需要升级随包数据时，可手动复制远端文件后发版。

远端地址：
https://raw.githubusercontent.com/danielgzd/DeviceMapping/main/config/device-mapping.json

上游：https://api.ipsw.me/v4/devices 。设备数组保留上游字段，外层增加正整数 `version`。仅数据变化时递增版本。上游返回空数据、重复标识或无效字段时任务失败，不覆盖文件；上游未返回的历史设备保留，避免新机型临时缺失。历史数据保留意味着删除或错误记录需要维护者人工修正。名称允许重复，标识不得重复。

```json
{
  "version": 2,
  "devices": [
    {"identifier": "iPhone19,4", "name": "iPhone Duo", "boards": []}
  ]
}
```

## iOS 接入

整体复制 `DeviceMapping/DeviceInfo/`，两个文件加入 App Target，JSON 加入 Copy Bundle Resources，作为普通 group 资源复制到 Bundle 根目录。

```swift
let identifier = DeviceInfo.getDeviceId() // 机型标识，不是每台设备的唯一 ID
let name = DeviceInfo.getDeviceName()
let pad = DeviceInfo.getDeviceName(for: "iPad19,1")
let locale = DeviceInfo.getDeviceLocale()

// 在 App 启动后异步刷新；同步名称查询不会自动请求网络。
Task {
    let accepted = await DeviceInfo.refreshConfiguration()
    // 更新页面时在 MainActor 上执行。
    print(accepted, DeviceInfo.getDeviceName())
}
```

下载超时、HTTP 失败、JSON 无效或超过 2 MB，返回 false，保留已有数据。成功响应只有版本不低于缓存才被接受，同版本保留原缓存。远端有效数据缓存到 UserDefaults，后续启动可离线使用。演示 App 通过 `.task` 展示刷新结果。

查询顺序：UserDefaults 已缓存远端配置 → 内置 JSON → 原始硬件标识 → `unknown`（无法取得标识）。业务可继续自行下发增量或全量配置：

```swift
UserDefaults.standard.set(jsonData, forKey: DeviceInfo.configurationKey)
let name = DeviceInfo.getDeviceName()
```

查询顺序不比较内置和缓存版本；version 用于远端刷新时避免回退。增量配置缺少某机型时会查询内置数据。每次名称查询重新读取本地配置，不适合在动画等高频回调中反复调用。App Group 可通过 `userDefaults:` 参数注入共享缓存。

## 每日自动任务

`.github/workflows/update-devices.yml` 每日北京时间 09:23 执行，支持手动触发。任务验证脚本后获取上游，生成 `config/device-mapping.json`，有变化才提交。仅需要 GitHub 自动提供的 GITHUB_TOKEN，无需自定义密钥。定时执行可能延迟，公开仓库长期无活动也可能被 GitHub 暂停，需要在 Actions 中重新启用。

```sh
python3 scripts/update_devices.py
python3 -m unittest discover -s scripts -p 'test_*.py'
swiftc DeviceMapping/DeviceInfo/DeviceInfo.swift Tests/main.swift -o /tmp/device-mapping-tests
/tmp/device-mapping-tests DeviceMapping/DeviceInfo/device-mapping.json
xcodebuild -project DeviceMapping.xcodeproj -scheme DeviceMapping -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

同步脚本仅使用 Python 标准库；失败时退出非零并保留旧文件。默认分支为 main，配置发布通过公开 GitHub Raw 文件，无需 GitHub Pages。
