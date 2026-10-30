# DeviceMapping

**iOS 设备名称查询工具，支持远端更新与本地配置兜底。**

[![每半月同步](https://github.com/danielgzd/DeviceMapping/actions/workflows/update-devices.yml/badge.svg)](https://github.com/danielgzd/DeviceMapping/actions/workflows/update-devices.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![iOS 15+](https://img.shields.io/badge/iOS-15%2B-black.svg)](#快速接入)

将 `iPhone19,4` 等硬件标识转换为设备名称。通过 IPSW.me 每半月同步机型数据，支持离线查询，也支持业务自行下发配置。

| 能力 | 说明 |
| --- | --- |
| 系统支持 | 工具支持 iOS 15+；演示 App 支持 iOS 16+ |
| 接入方式 | 复制一个文件夹，无第三方依赖 |
| 数据更新 | GitHub Actions 每半月生成远端 JSON |
| 离线可用 | 远端缓存与随包配置共同提供查询数据 |
| 异常处理 | 配置无效不影响查询，未收录机型返回原始标识 |

[快速接入](#快速接入) · [配置规则](#配置规则) · [自动更新](#自动更新) · [开发验证](#开发验证)

## 快速接入

### 1. 复制工具目录

将以下目录复制到业务项目，并把两个文件加入 App Target：

```text
DeviceMapping/DeviceInfo/
├── DeviceInfo.swift       # 查询、配置解析与远端刷新
└── device-mapping.json    # 随 App 打包的保底配置
```

确认 JSON 位于 **Build Phases → Copy Bundle Resources** 中。使用普通 Xcode group，将 JSON 复制到 Bundle 根目录；若使用保留目录层级的 folder reference，需要相应调整资源查找路径。

### 2. 查询设备信息

```swift
// 当前机型标识，不是每台设备的唯一 ID
let identifier = DeviceInfo.getDeviceId()

// 当前设备名称
let name = DeviceInfo.getDeviceName()

// 查询指定机型
let modelName = DeviceInfo.getDeviceName(for: "iPad19,1")

// 系统首选语言
let locale = DeviceInfo.getDeviceLocale()
```

名称允许重复，硬件标识用于查询。同一型号的多台设备可能拥有相同标识。

### 3. 按需刷新远端配置

同步查询方法只读取本地数据。需要更新时，在 App 启动后显式调用：

```swift
Task {
    let accepted = await DeviceInfo.refreshConfiguration()
    print(accepted, DeviceInfo.getDeviceName())
}
```

有效配置会原子写入 Application Support 缓存文件，后续启动可离线使用。需要更新界面时，请在 `MainActor` 上执行界面操作。

> 刷新失败会保留已有缓存；业务尚未缓存任何配置时，直接使用内置 JSON。

## 配置规则

### 查询顺序

```text
取得机型标识
  ├─ 无法取得 → unknown
  └─ 取得成功
      ├─ 缓存配置中找到 → 返回缓存名称
      ├─ 内置配置中找到 → 返回内置名称
      └─ 均未找到 → 返回原始机型标识
```

支持增量和全量配置。例如业务只下发 iPhone 数据时，iPad 仍可从内置 JSON 获取名称。

### JSON 格式

设备数组沿用 [IPSW.me 接口](https://api.ipsw.me/v4/devices)格式，外层增加 `version` 和 `devices`：

```json
{
  "version": 2,
  "devices": [
    {
      "identifier": "iPhone19,4",
      "name": "iPhone Duo",
      "boards": []
    }
  ]
}
```

| 字段 | 规则 |
| --- | --- |
| `version` | 正整数，记录配置版本 |
| `devices` | 非空设备数组 |
| `identifier` | 非空且不能重复 |
| `name` | 非空，允许不同设备重名 |
| 其他字段 | 保留上游字段；客户端查询仅依赖 `identifier` 与 `name` |

**版本与查询优先级是两套规则：**

- 刷新远端时，版本低于已有缓存会被拒绝；同版本保留原缓存。
- 查询名称时，优先查缓存，再查内置配置，不比较两者版本。

HTTP 失败、超时、无效 JSON 或超过 2 MB 的响应都会使刷新返回 `false`，已有缓存不变。

### 业务自行下发

业务也可以直接保存带版本号的 JSON Data：

```swift
let saved = DeviceInfo.saveConfiguration(jsonData)

// 下一次查询即可读取，无需重启
let name = DeviceInfo.getDeviceName()

// 按需清除缓存，恢复使用内置配置
if let url = DeviceInfo.configurationCacheURL {
    try? FileManager.default.removeItem(at: url)
}
```

默认缓存位置为 `Library/Application Support/DeviceMapping/device-mapping.json`。支持通过 `cacheURL:` 注入 App Group 文件地址。保存前校验内容和版本，原子写入失败会返回 false；读取最多 2 MB + 1 字节，超限、损坏或缺失文件均忽略并查询内置配置。

此版本不再读写 UserDefaults，也不会自动迁移旧键。升级后可重新刷新远端或通过 `saveConfiguration` 写入业务配置；原有偏好设置键不会被自动删除。

每次名称查询会重新读取本地配置，建议获取后复用结果，避免在动画等高频回调中重复调用。

## 自动更新

**远端 JSON：** [查看或获取配置](https://raw.githubusercontent.com/danielgzd/DeviceMapping/main/config/ios.json)

**执行记录：** [每半月同步设备映射](https://github.com/danielgzd/DeviceMapping/actions/workflows/update-devices.yml)

| 文件 | 用途 |
| --- | --- |
| [`config/device-mapping.json`](config/device-mapping.json) | 定时生成并对外提供的远端配置 |
| [`DeviceMapping/DeviceInfo/device-mapping.json`](DeviceMapping/DeviceInfo/device-mapping.json) | 独立的随包保底快照 |
| [`scripts/update_devices.py`](scripts/update_devices.py) | 获取、校验、合并并生成配置 |
| [每日工作流](.github/workflows/update-devices.yml) | 定时运行与自动提交 |

任务在 **每月 1 日和 16 日，北京时间 09:23** 执行，也支持在 Actions 页面手动运行：

1. 运行同步脚本测试。
2. 获取 IPSW.me 设备列表并校验。
3. 合并历史记录，生成远端 JSON。
4. 每次成功构建均递增版本、写入构建时间并提交。

上游返回空数据、重复标识或无效字段时，任务失败并保留旧文件。上游暂时缺失的历史设备会保留，因此删除错误记录需要维护者人工修正。

随包 JSON **不会被定时任务修改**。需要升级内置数据时，可将远端配置复制到工具目录，随下次 App 发版更新。

工作流使用 GitHub 自动提供的 `GITHUB_TOKEN`，无需额外密钥或 GitHub Pages。定时执行可能延迟；公开仓库长期无活动时，GitHub 可能暂停定时任务，需要重新启用。

## 开发验证

使用 Xcode 打开 `DeviceMapping.xcodeproj` 运行演示 App。真机运行需选择自己的签名团队。

**同步脚本与测试**（仅依赖 Python 标准库）：

```sh
python3 scripts/update_devices.py
python3 -m unittest discover -s scripts -p 'test_*.py'
```

**Swift 逻辑检查**（macOS）：

```sh
swiftc DeviceMapping/DeviceInfo/DeviceInfo.swift Tests/main.swift \
  -o /tmp/device-mapping-tests

/tmp/device-mapping-tests DeviceMapping/DeviceInfo/device-mapping.json
```

**模拟器构建：**

```sh
xcodebuild -project DeviceMapping.xcodeproj \
  -scheme DeviceMapping \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build
```

## 许可证与数据来源

Copyright © 2026 gdd. 项目代码采用 [MIT License](LICENSE)。

主要数据源为 [IPSW.me](https://api.ipsw.me/v4/devices)。本地补充记录参考 [DeviceKit](https://github.com/devicekit/DeviceKit)、[AppleDB](https://appledb.dev/device-selection/iPad-mini.html) 等公开资料。项目许可证不替代第三方数据适用的条款。

## 按设备类型获取配置

每日脚本同时生成以下文件，工具默认刷新 `ios.json`：

| 文件 | 设备范围 |
| --- | --- |
| [ios.json](config/ios.json) | iPhone、iPad、iPod touch |
| [iphone.json](config/iphone.json) | 仅 iPhone |
| [ipad.json](config/ipad.json) | 仅 iPad |
| [device-mapping.json](config/device-mapping.json) | 全部设备 |

分类按 identifier 前缀筛选，各文件每次成功构建均递增版本。首次分类文件沿用全量版本；后续不同配置流的版本独立，切换文件地址时建议清除原缓存，避免版本比较阻止新配置保存。

随包的 `DeviceMapping/DeviceInfo/device-mapping.json` 保留全量设备，定时任务不覆盖，偶尔手动更新即可：

```sh
cp config/device-mapping.json DeviceMapping/DeviceInfo/device-mapping.json
```

这样正常使用只需下载 iOS 分类；远端缺少机型时仍能查询本地全量保底配置。

### config 分类目录

```text
config/
├── device-mapping.json   # 全量设备
├── ios.json              # iPhone + iPad + iPod touch
├── iphone.json           # iPhone
├── ipad.json             # iPad
├── ipod.json             # iPod touch
├── mac.json              # Mac（包含 iMac、MacBook、VirtualMac、ADP）
├── watch.json            # Apple Watch
├── appletv.json          # Apple TV
├── homepod.json          # HomePod（AudioAccessory）
├── vision.json           # Apple Vision（RealityDevice）
├── ibridge.json          # iBridge
└── simulator.json        # 模拟器架构标识
```

每个设备归入一个基础类别，`ios.json` 是移动设备的合并视图，`device-mapping.json` 是全部类别的合并视图。未来无法识别类别的标识会进入 `other.json`；没有记录的类别不生成空文件。分类文件从全量数据重新筛选，防止分类规则调整后残留旧记录。App 内置全量 JSON 保持不变。

## Telegram 通知

在仓库 Settings → Secrets and variables → Actions 添加两个 Repository Secrets：

| Secret | 内容 |
| --- | --- |
| `TELEGRAM_BOT_TOKEN` | BotFather 创建的机器人的 Token |
| `TELEGRAM_CHAT_ID` | 接收消息的个人或群组 Chat ID |

个人接收需先向机器人发送 `/start`；群组接收需将机器人加入群组并允许发送消息。Token 不要写入代码或聊天。未配置 Secrets 时跳过通知；仅在配置有更新或同步失败时发送，内容包含运行记录链接，无变化保持安静。可从 Actions 手动执行同步验证；无变化时不会发送测试消息。

这里的“每半月”为每月 1 日、16 日，并非严格每隔 15×24 小时。

### 构建元信息

所有生成配置包含 `version` 和 `buildTime`。每次成功任务均将各文件版本加 1，所有分类共享本次构建时间，使用带 `+08:00` 时区的 ISO 8601 字符串。数据没有变化也会生成新版本，因此成功构建会触发 Telegram 更新通知。任务仅由每半月定时或手动操作触发，普通代码推送不触发，避免重复构建。内置 JSON 本次补上构建时间，后续仍按需手动更新。
