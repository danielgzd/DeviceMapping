// Copyright © 2026 gdd. All rights reserved.
// 设备机型映射工具：复制本文件及 Resources/device-mapping.json 即可接入。

import Foundation

func data(_ version: Int, _ name: String = "测试设备") -> Data {
    try! JSONEncoder().encode(DeviceMappingConfiguration(version: version, devices: [.init(identifier: "test,1", name: name)]))
}
let broken = Data("invalid".utf8)
assert(DeviceMappingStore(bundledData: data(2), cachedData: data(1)).source == .cached)
assert(DeviceMappingStore(bundledData: data(1), cachedData: data(2)).source == .cached)
assert(DeviceMappingStore(bundledData: data(2), cachedData: data(2)).source == .cached)
assert(DeviceMappingStore(bundledData: data(1), cachedData: broken).source == .bundled)
assert(DeviceMappingStore(bundledData: broken, cachedData: data(1)).source == .cached)
assert(DeviceMappingStore(bundledData: nil, cachedData: nil).name(for: "unknown,1") == "unknown,1")
assert(DeviceMappingStore(bundledData: data(0)).source == .unavailable)
assert(DeviceMappingStore(bundledData: data(1, " ")).source == .unavailable)
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let bundled = try Data(contentsOf: url)
let store = DeviceMappingStore(bundledData: bundled)
assert(store.source == .bundled)
assert(store.name(for: "iPad19,1") == "iPad mini (A20 Pro)")
assert(store.name(for: "iPhone19,4") == "iPhone Duo")
let suite = "DeviceMappingTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
func cachedStore() -> DeviceMappingStore {
    DeviceMappingStore(bundledData: bundled, cachedData: DeviceMappingStore.cachedData(from: defaults))
}
assert(cachedStore().source == .bundled)
defaults.set(data(3), forKey: DeviceMappingStore.userDefaultsKey)
assert(cachedStore().configuration?.version == 3)
defaults.set(String(data: data(3), encoding: .utf8)!, forKey: DeviceMappingStore.userDefaultsKey)
assert(cachedStore().configuration?.version == 3)
defaults.set(["version": 4, "devices": [["identifier": "test,1", "name": "字典设备"]]], forKey: DeviceMappingStore.userDefaultsKey)
assert(cachedStore().name(for: "test,1") == "字典设备")
defaults.set(broken, forKey: DeviceMappingStore.userDefaultsKey)
assert(cachedStore().source == .bundled)
defaults.set(data(2), forKey: DeviceMappingStore.userDefaultsKey)
assert(cachedStore().source == .cached)
defaults.set(123, forKey: DeviceMappingStore.userDefaultsKey)
assert(cachedStore().source == .bundled)
defaults.removeObject(forKey: DeviceMappingStore.userDefaultsKey)
assert(cachedStore().source == .bundled)
let raw = Data("[{\"identifier\":\"test,1\",\"name\":\"设备\"}]".utf8)
assert(DeviceMappingStore(bundledData: raw).source == .unavailable)
let duplicate = try! JSONEncoder().encode(DeviceMappingConfiguration(version: 5, devices: [.init(identifier: "a", name: "A"), .init(identifier: "a", name: "B")]))
assert(DeviceMappingStore(bundledData: bundled, cachedData: duplicate).source == .bundled)
let extended = Data("{\"version\":5,\"devices\":[{\"identifier\":\"test,1\",\"name\":\"附加字段\",\"boards\":[],\"cpid\":123}]}".utf8)
assert(DeviceMappingStore(bundledData: bundled, cachedData: extended).name(for: "test,1") == "附加字段")
let repeatedNames = DeviceMappingConfiguration(version: 6, devices: [.init(identifier: "a,1", name: "同名设备"), .init(identifier: "a,2", name: "同名设备")])
let repeatedData = try! JSONEncoder().encode(repeatedNames)
let repeatedStore = DeviceMappingStore(bundledData: repeatedData)
assert(repeatedStore.name(for: "a,1") == "同名设备")
assert(repeatedStore.name(for: "a,2") == "同名设备")
defaults.set(repeatedData, forKey: DeviceInfo.configurationKey)
assert(DeviceInfo.getDeviceName(for: "a,2", userDefaults: defaults) == "同名设备")
let malformed = ["null", "[]", "{}", "{\"version\":true,\"devices\":[]}", "{\"version\":999999999999999999999999999,\"devices\":[]}"]
for text in malformed {
    assert(DeviceMappingStore(bundledData: bundled, cachedData: Data(text.utf8)).source == .bundled)
}
assert(DeviceMappingStore(bundledData: bundled, cachedData: Data(repeating: 32, count: 2 * 1024 * 1024 + 1)).source == .bundled)
DispatchQueue.concurrentPerform(iterations: 200) { _ in
    assert(DeviceInfo.getDeviceName(for: "a,2", userDefaults: defaults) == "同名设备")
}
print("异常配置、超限数据及 200 次并发查询检查通过")

let partial = DeviceMappingStore(bundledData: bundled, cachedData: data(999))
assert(partial.name(for: "test,1") == "测试设备")
assert(partial.name(for: "iPad19,1") == "iPad mini (A20 Pro)")
assert(partial.name(for: "future,1") == "future,1")
assert(partial.name(for: "") == "unknown")
assert(partial.name(for: "   ") == "unknown")
assert(partial.name(for: "unknown") == "unknown")
let override = DeviceMappingStore(bundledData: data(10, "内置名称"), cachedData: data(1, "业务名称"))
assert(override.name(for: "test,1") == "业务名称")
print("增量配置、本地补查、业务优先及未知标识检查通过")
