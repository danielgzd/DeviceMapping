// Copyright © 2026 gdd. Licensed under the MIT License.
// 设备机型映射工具：整体复制 DeviceInfo 文件夹并将 JSON 加入 Copy Bundle Resources 即可接入。

import Foundation
import Darwin

/// 设备机型工具。同步查询只读本地；可显式调用异步方法刷新远端配置。
///
/// 配置来自 Bundle 与 Application Support 缓存文件，按机型优先查询业务缓存，缺失时查询内置配置。
/// 名称允许重复，identifier 必须唯一。名称用于展示，不能用作设备唯一标识。
public final class DeviceInfo {
    private init() {}

    /// 默认持久缓存位置。目录不可用时返回 nil，查询仍可使用随包配置。
    public static var configurationCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DeviceMapping", isDirectory: true)
            .appendingPathComponent("device-mapping.json")
    }

    /// 仓库每日生成的远端配置。查询名称不会自动发起请求。
    public static let remoteConfigurationURL = URL(string:
        "https://raw.githubusercontent.com/danielgzd/DeviceMapping/main/config/ios.json"
    )

    /// 异步刷新远端配置，建议 App 启动后调用，不阻塞页面展示。
    /// 校验通过且版本不低于现有缓存时保存；失败保留已有缓存，返回 false。
    /// - Returns: 本次响应是否成功验证并接受（相同版本保留原缓存）。
    @discardableResult
    public static func refreshConfiguration(
        from url: URL? = remoteConfigurationURL,
        cacheURL: URL? = configurationCacheURL
    ) async -> Bool {
        guard let url, url.scheme == "https" else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            // 流式接收并限制大小，避免异常响应无限占用内存。
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  response.expectedContentLength <= 2 * 1024 * 1024 else { return false }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 2 * 1024 * 1024 else { return false }
                data.append(byte)
            }
            _ = try DeviceMappingConfiguration.decode(data)
            // 写入段串行执行，避免并发刷新中较旧的请求覆盖较新的版本。
            return saveConfiguration(data, at: cacheURL)
        } catch {
            return false
        }
    }

    private static let configurationLock = NSLock()

    /// 保存业务下发的完整或增量 JSON。仅接受有效配置，拒绝版本回退。
    /// 原子写入失败返回 false，已有缓存保持不变；不使用 UserDefaults。
    @discardableResult
    public static func saveConfiguration(_ data: Data, at cacheURL: URL? = configurationCacheURL) -> Bool {
        guard let cacheURL, cacheURL.isFileURL,
              let incoming = try? DeviceMappingConfiguration.decode(data) else { return false }
        configurationLock.lock()
        defer { configurationLock.unlock() }
        if let cached = DeviceMappingStore.cachedData(at: cacheURL),
           let existing = try? DeviceMappingConfiguration.decode(cached) {
            guard incoming.version >= existing.version else { return false }
            if incoming.version == existing.version { return true }
        }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 返回机型硬件标识，例如 iPhone19,4；同一机型的多台设备会返回相同值。
    /// 模拟器优先返回模拟机型标识，系统读取失败时返回 unknown。
    public static func getDeviceId() -> String {
        
        #if targetEnvironment(simulator)
        if let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !model.isEmpty {
            return model
        }
        #endif
        var info = utsname()
        guard uname(&info) == 0 else { return "unknown" }
        return withUnsafeBytes(of: &info.machine) {
            String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }

    /// 获取当前设备展示名称。每次查询重新读取配置，业务缓存写入后下次调用即生效。
    public static func getDeviceName() -> String {
        getDeviceName(for: getDeviceId())
    }

    /// 根据指定机型查询名称。未收录或两份配置均不可用时返回原始 identifier。
    /// - Parameters:
    ///   - identifier: 机型硬件标识；不对名称做反向唯一匹配。
    ///   - bundle: 内置 device-mapping.json 所在 Bundle，默认主应用。
    ///   - cacheURL: 缓存文件路径，默认 Application Support，可注入 App Group 文件地址。
    public static func getDeviceName(
        for identifier: String,
        bundle: Bundle = .main,
        cacheURL: URL? = configurationCacheURL
    ) -> String {
        DeviceMappingStore(bundle: bundle, cacheURL: cacheURL).name(for: identifier)
    }

    /// 返回系统首选语言标识（例如 zh-Hans-CN），无可用值时返回 unknown。
    public static func getDeviceLocale() -> String {
        Locale.preferredLanguages.first ?? "unknown"
    }
}

// MARK: - 配置模型与选择逻辑（内部实现）

/// 单调递增的整数版本。发布配置时必须递增 version。
struct DeviceMappingConfiguration: Codable, Equatable {
    let version: Int
    let devices: [Device]

    /// 与 IPSW.me 数组元素兼容。映射只依赖 identifier、name，忽略 boards 等附加字段。
    struct Device: Codable, Equatable {
        let identifier: String
        let name: String
    }

    static func decode(_ data: Data) throws -> Self {
        // 映射配置体积应很小，拒绝异常大数据，避免解码造成明显内存和 CPU 开销。
        guard data.count <= 2 * 1024 * 1024 else {
            throw ConfigurationError.invalidContent
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version > 0, !value.devices.isEmpty,
              value.devices.allSatisfy({ !$0.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ConfigurationError.invalidContent
        }
        guard Set(value.devices.map(\.identifier)).count == value.devices.count else {
            throw ConfigurationError.invalidContent
        }
        return value
    }

    enum ConfigurationError: Error { case invalidContent }
}

struct DeviceMappingStore {

    enum Source: String { case bundled, cached, unavailable }
    let configuration: DeviceMappingConfiguration?
    let source: Source
    private let bundledConfiguration: DeviceMappingConfiguration?
    private let cachedConfiguration: DeviceMappingConfiguration?

    /// 两份配置独立校验。业务配置可以是增量，按机型优先查询业务缓存。
    /// version 保留用于业务追踪，不影响查询优先级，即低版本业务配置也优先。
    init(bundledData: Data?, cachedData: Data? = nil) {
        let bundled = bundledData.flatMap { try? DeviceMappingConfiguration.decode($0) }
        let cached = cachedData.flatMap { try? DeviceMappingConfiguration.decode($0) }
        bundledConfiguration = bundled
        cachedConfiguration = cached
        if let cached {
            configuration = cached
            source = .cached
        } else if let bundled {
            configuration = bundled
            source = .bundled
        } else {
            configuration = nil
            source = .unavailable
        }
    }

    /// 仅从应用资源及缓存文件 读取，不产生网络请求或写入缓存。
    init(bundle: Bundle = .main, cacheURL: URL? = DeviceInfo.configurationCacheURL) {
        let bundledData = bundle.url(forResource: "device-mapping", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let cachedData = Self.cachedData(at: cacheURL)
        self.init(bundledData: bundledData, cachedData: cachedData)
    }

    /// 限量读取，文件异常或过大时忽略缓存。最多读取 2 MB + 1 字节。
    static func cachedData(at url: URL?) -> Data? {
        guard let url, url.isFileURL,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2 * 1024 * 1024 + 1),
              data.count <= 2 * 1024 * 1024 else { return nil }
        return data
    }

    func name(for identifier: String) -> String {
        // 无硬件标识时无法查询，统一返回 unknown；普通未知机型保留原始标识。
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              identifier != "unknown" else { return "unknown" }
        if let name = cachedConfiguration?.devices.first(where: { $0.identifier == identifier })?.name {
            return name
        }
        if let name = bundledConfiguration?.devices.first(where: { $0.identifier == identifier })?.name {
            return name
        }
        return identifier
    }
}
