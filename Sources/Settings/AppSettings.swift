import Foundation
import Combine

/// 用户可配置的服务端参数。源码里不留任何真实地址或账号，
/// 首次启动时为空，需要在设置页填写。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var serverAddress: String {
        didSet { if serverAddress != oldValue { persist() } }
    }

    @Published var username: String {
        didSet { if username != oldValue { persist() } }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let serverAddress = "serverAddress"
        static let username = "username"
    }

    private init() {
        serverAddress = defaults.string(forKey: Keys.serverAddress) ?? ""
        username = defaults.string(forKey: Keys.username) ?? ""
    }

    // MARK: - 校验

    /// 规整后的服务器地址；不合法时为 nil。
    ///
    /// 只接受 http/https，并去掉结尾多余的斜杠，避免和
    /// appendingPathComponent 拼出双斜杠。
    var normalizedServerURL: URL? {
        var text = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard !text.isEmpty else { return nil }

        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }

    var normalizedUsername: String? {
        let text = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var isConfigured: Bool {
        normalizedServerURL != nil && normalizedUsername != nil
    }

    // MARK: - 校验反馈

    /// 地址非空但不合法时的原因，用于设置页内联提示。
    func serverAddressProblem(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return "地址格式不正确"
        }
        if scheme != "https" && scheme != "http" {
            return "只支持 http:// 或 https://"
        }
        if scheme == "http" {
            return "iOS 会拦截明文 http 请求，请使用 https://"
        }
        if url.host?.isEmpty ?? true {
            return "缺少主机名"
        }
        return nil
    }

    // MARK: - 持久化

    private func persist() {
        defaults.set(serverAddress, forKey: Keys.serverAddress)
        defaults.set(username, forKey: Keys.username)
    }
}
