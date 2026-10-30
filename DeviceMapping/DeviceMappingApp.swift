// Copyright © 2026 gdd. Licensed under the MIT License.
// 设备机型映射工具：复制本文件及 Resources/device-mapping.json 即可接入。

import SwiftUI

@main
struct DeviceMappingApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    private var store: DeviceMappingStore { DeviceMappingStore() }
    @State private var refreshMessage = "尚未刷新远端配置"
    @State private var identifier = "iPad19,1"

    var body: some View {
        NavigationStack {
            Form {
                Section("当前设备") {
                    LabeledContent("设备名称", value: DeviceInfo.getDeviceName())
                    LabeledContent("硬件标识", value: DeviceInfo.getDeviceId())
                }
                Section("配置状态") {
                    Text(refreshMessage)
                    LabeledContent("配置版本", value: store.configuration.map { String($0.version) } ?? "不可用")
                    LabeledContent("配置来源", value: store.source == .bundled ? "随应用内置" : store.source == .cached ? "本地缓存" : "读取失败")
                    LabeledContent("映射数量", value: String(store.configuration?.devices.count ?? 0))
                }
                Section("查询设备") {
                    TextField("例如 iPhone19,4", text: $identifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("设备名称", value: DeviceInfo.getDeviceName(for: identifier))
                }
            }
            .navigationTitle("设备映射")
            .task {
                let success = await DeviceInfo.refreshConfiguration()
                refreshMessage = success ? "远端配置已验证" : "远端不可用，使用已有缓存与内置配置"
            }
        }
    }
}
