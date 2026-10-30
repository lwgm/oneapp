import Foundation

// MARK: - 错误

enum APIError: LocalizedError {
    /// 还没填服务器地址或用户名。
    case notConfigured
    /// 地址本身不合法（协议、主机名）。
    case invalidAddress(String)
    /// 连不上：DNS、拒绝连接、超时、断网。
    case unreachable(String)
    /// 证书问题，或用了 http 被 ATS 拦下。
    case insecureConnection(String)
    /// 连上了，但返回的不是我们这个接口的内容。
    case notOurServer
    /// 403：用户名不在允许名单，或服务端未开启该功能。
    case notAllowed(String)
    /// 401：服务端启用了 token。
    case authRequired
    /// 其它业务错误，直接展示服务端文案。
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未配置服务器地址或用户名"
        case .invalidAddress(let detail):
            return detail
        case .unreachable(let detail):
            return detail
        case .insecureConnection(let detail):
            return detail
        case .notOurServer:
            return "这个地址返回的不是接口数据"
        case .notAllowed(let message):
            return message
        case .authRequired:
            return "服务端要求身份认证"
        case .server(let message):
            return message
        }
    }

    /// 把底层网络错误翻译成能指导用户下一步的说明。
    static func from(_ error: Error) -> APIError {
        guard let urlError = error as? URLError else {
            return .unreachable(error.localizedDescription)
        }

        switch urlError.code {
        case .cannotFindHost:
            return .unreachable("找不到这个主机名，请检查地址是否拼错")
        case .cannotConnectToHost:
            return .unreachable("无法连接该地址和端口，请确认服务已启动、端口正确")
        case .dnsLookupFailed:
            return .unreachable("域名解析失败，请检查地址或当前网络")
        case .notConnectedToInternet:
            return .unreachable("设备当前没有网络连接")
        case .networkConnectionLost:
            return .unreachable("连接被中断，请稍后重试")
        case .timedOut:
            return .unreachable("连接超时，服务器没有响应")
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot:
            return .insecureConnection("HTTPS 证书未通过验证，请确认地址与证书配置")
        case .appTransportSecurityRequiresSecureConnection:
            return .insecureConnection("iOS 不允许明文 http 请求，请改用 https://")
        default:
            return .unreachable(urlError.localizedDescription)
        }
    }
}

// MARK: - 给界面用的错误描述

/// 把错误整理成「标题 / 说明 / 是否该去设置里改」三件事，
/// 好让错误页告诉用户下一步做什么，而不是只丢一句原因。
struct LoadError {
    let title: String
    let message: String
    /// true 表示问题出在配置上，展示「去设置」比「重试」更有效。
    let suggestsSettings: Bool

    init(_ error: APIError) {
        let resolvedTitle: String
        let resolvedMessage: String
        let resolvedSuggestsSettings: Bool

        switch error {
        case .notConfigured:
            resolvedTitle = "还没连接服务器"
            resolvedMessage = "请在设置里填写服务器地址和用户名。"
            resolvedSuggestsSettings = true
        case .invalidAddress(let detail):
            resolvedTitle = "服务器地址不正确"
            resolvedMessage = detail
            resolvedSuggestsSettings = true
        case .insecureConnection(let detail):
            resolvedTitle = "连接不安全"
            resolvedMessage = detail
            resolvedSuggestsSettings = true
        case .notOurServer:
            resolvedTitle = "地址不对"
            resolvedMessage = "这个地址能连上，但返回的不是书籍接口。请确认填的是后端根地址，末尾不要带路径。"
            resolvedSuggestsSettings = true
        case .notAllowed(let detail):
            resolvedTitle = "没有访问权限"
            resolvedMessage = detail.isEmpty
                ? "这个用户名不在服务器的允许名单里，请到设置中确认。"
                : "\(detail)。请确认设置里的用户名已在服务器允许名单中。"
            resolvedSuggestsSettings = true
        case .authRequired:
            resolvedTitle = "需要身份认证"
            resolvedMessage = "服务端启用了访问令牌，当前版本还不支持填写。"
            resolvedSuggestsSettings = true
        case .unreachable(let detail):
            resolvedTitle = "无法连接服务器"
            resolvedMessage = detail
            resolvedSuggestsSettings = false
        case .server(let detail):
            resolvedTitle = "无法加载书库"
            resolvedMessage = detail
            resolvedSuggestsSettings = false
        }

        title = resolvedTitle
        message = resolvedMessage
        suggestsSettings = resolvedSuggestsSettings
    }
}

// MARK: - Wire 字段

/// 服务端约定的字段名，只在这里出现一次。
/// 界面上一律称「用户名」，不暴露这个名称。
private enum Wire {
    static let identity = "openid"
}

// MARK: - 统一响应信封

private struct Envelope: Decodable {
    let success: Bool
    let code: Int?
    let message: String?
}

// MARK: - 上传

enum UploadOutcome {
    case uploaded(calibreID: Int?)
    case duplicate(calibreID: Int?, title: String?)
    case timedOut
    case forbidden(String)
    case failed(String)
}

private struct UploadResponse: Decodable {
    let success: Bool
    let code: Int?
    let message: String?
    let bookID: Int?
    let cost: String?
    let dup: Bool?

    enum CodingKeys: String, CodingKey {
        case success, code, message, cost, dup
        case bookID = "book_id"
    }
}

// MARK: - 历史

struct HistoryPage: Decodable {
    let success: Bool
    let message: String?
    let total: Int?
    let count: Int?
    let hasMore: Bool?
    let nextBeforeID: Int?
    let items: [Book]

    enum CodingKeys: String, CodingKey {
        case success, message, total, count, items
        case hasMore = "has_more"
        case nextBeforeID = "next_before_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        message = try container.decodeIfPresent(String.self, forKey: .message)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
        nextBeforeID = try container.decodeIfPresent(Int.self, forKey: .nextBeforeID)
        items = try container.decodeIfPresent([Book].self, forKey: .items) ?? []
    }
}

// MARK: - 删除

struct DeleteResult: Decodable {
    let success: Bool
    let code: Int?
    let message: String?
    let removedRecords: Int?
    let deletedInLibrary: [Int]
    let keptInLibrary: [Int]

    enum CodingKeys: String, CodingKey {
        case success, code, message
        case removedRecords = "removed_records"
        case deletedInLibrary = "deleted_in_library"
        case keptInLibrary = "kept_in_library"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        code = try container.decodeIfPresent(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        removedRecords = try container.decodeIfPresent(Int.self, forKey: .removedRecords)
        deletedInLibrary = try container.decodeIfPresent([Int].self, forKey: .deletedInLibrary) ?? []
        keptInLibrary = try container.decodeIfPresent([Int].self, forKey: .keptInLibrary) ?? []
    }

    /// 库里仍有其他用户拥有这本书时，本次只把自己的记录移除了。
    var wasKeptInLibrary: Bool { !keptInLibrary.isEmpty }
}

// MARK: - 删除上传记录

/// `/history/delete` 的响应：只清 failed / pending 记录，不碰 Calibre。
struct HistoryDeleteResult: Decodable {
    let success: Bool
    let code: Int?
    let message: String?
    let removedRecords: Int?

    enum CodingKeys: String, CodingKey {
        case success, code, message
        case removedRecords = "removed_records"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        code = try container.decodeIfPresent(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        removedRecords = try container.decodeIfPresent(Int.self, forKey: .removedRecords)
    }
}

// MARK: - 连接测试

enum ConnectionTestResult {
    case allowed(String)
    case denied(String)
    case failed(String)
}

private struct AccessCheck: Decodable {
    let success: Bool
    let code: Int?
    let message: String?
    let allowed: Bool?
}

// MARK: - 客户端

final class APIClient {
    static let shared = APIClient()

    private let uploadSession: URLSession
    private let plainSession: URLSession
    private let settings: AppSettings

    private init() {
        let uploadConfiguration = URLSessionConfiguration.default
        // 上传服务端最长等 50 秒，文档建议客户端超时 ≥ 70 秒。
        uploadConfiguration.timeoutIntervalForRequest = 90
        uploadConfiguration.timeoutIntervalForResource = 120
        uploadConfiguration.waitsForConnectivity = true
        uploadSession = URLSession(configuration: uploadConfiguration)

        let plainConfiguration = URLSessionConfiguration.default
        plainConfiguration.timeoutIntervalForRequest = 25
        plainConfiguration.waitsForConnectivity = true
        plainSession = URLSession(configuration: plainConfiguration)

        settings = .shared
    }

    // MARK: 封面

    /// 拼 `/cover?username=…&book_id=…&isbn=…`。
    /// 这个接口成功时返回二进制图片，且不需要 Authorization 头，
    /// 因此可以直接交给图片加载层。
    func coverURL(for book: Book) -> URL? {
        guard let base = settings.normalizedServerURL,
              let name = settings.normalizedUsername,
              let bookID = book.bookID,
              !book.isbn.isEmpty else {
            return nil
        }

        var components = URLComponents(
            url: base.appendingPathComponent("cover"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: Wire.identity, value: name),
            URLQueryItem(name: "book_id", value: String(bookID)),
            URLQueryItem(name: "isbn", value: book.isbn)
        ]
        return components?.url
    }

    // MARK: 请求构造

    private func endpoint(_ path: String) throws -> URL {
        guard let base = settings.normalizedServerURL else {
            throw APIError.notConfigured
        }
        return base.appendingPathComponent(path)
    }

    private func identity() throws -> String {
        guard let name = settings.normalizedUsername else {
            throw APIError.notConfigured
        }
        return name
    }

    // MARK: 连接测试

    func testConnection() async -> ConnectionTestResult {
        let url: URL
        let name: String
        do {
            url = try endpoint("upload")
            name = try identity()
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? "配置不完整")
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: Wire.identity, value: name)]
        guard let finalURL = components?.url else {
            return .failed("地址格式不正确")
        }

        do {
            let data = try await get(finalURL)
            guard let check = try? JSONDecoder().decode(AccessCheck.self, from: data) else {
                return .failed("这个地址返回的不是接口数据，请确认填的是后端根地址")
            }
            guard check.success else {
                return .failed(check.message ?? "服务器拒绝了这次请求")
            }
            if check.allowed == true {
                return .allowed(check.message ?? "已开通")
            }
            return .denied(check.message ?? "功能暂时没开通")
        } catch let error as APIError {
            // 403 说明地址是通的，只是这个用户名没权限 —— 对测试连接来说是有价值的结论。
            if case .notAllowed(let message) = error {
                return .denied(message.isEmpty ? "功能暂时没开通" : message)
            }
            return .failed(error.errorDescription ?? "连接失败")
        } catch {
            return .failed(APIError.from(error).errorDescription ?? "连接失败")
        }
    }

    // MARK: 上传

    func upload(isbn: String, requestID: String) async -> UploadOutcome {
        let url: URL
        let name: String
        do {
            url = try endpoint("upload")
            name = try identity()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "配置不完整"
            return .failed(message)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "isbn": isbn,
            Wire.identity: name,
            "requestId": requestID
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await uploadSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.interpretUpload(data: data, statusCode: status)
        } catch let error as URLError where error.code == .timedOut {
            return .timedOut
        } catch {
            return .failed(APIError.from(error).errorDescription ?? "上传失败")
        }
    }

    static func interpretUpload(data: Data, statusCode: Int) -> UploadOutcome {
        let decoded = try? JSONDecoder().decode(UploadResponse.self, from: data)

        if let decoded, decoded.success {
            if decoded.dup == true {
                return .duplicate(
                    calibreID: decoded.bookID,
                    title: extractTitle(from: decoded.message)
                )
            }
            return .uploaded(calibreID: decoded.bookID)
        }

        let message = decoded?.message ?? "请求失败（HTTP \(statusCode)）"
        if statusCode == 502 && message.contains("超时") {
            return .timedOut
        }
        if statusCode == 403 {
            return .forbidden(message)
        }
        return .failed(message)
    }

    /// 重复扫同一本书时 message 形如「已存在: 书名」，把书名抽出来复用。
    static func extractTitle(from message: String?) -> String? {
        guard let message else { return nil }
        guard let range = message.range(of: "已存在:") ?? message.range(of: "已存在：") else {
            return nil
        }
        let title = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    // MARK: 历史

    func fetchHistory(limit: Int, beforeID: Int?) async throws -> HistoryPage {
        let base = try endpoint("history")
        let name = try identity()

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: Wire.identity, value: name),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let beforeID {
            queryItems.append(URLQueryItem(name: "before_id", value: String(beforeID)))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIError.notOurServer
        }

        let data = try await get(url)
        guard let page = try? JSONDecoder().decode(HistoryPage.self, from: data) else {
            throw APIError.notOurServer
        }
        guard page.success else {
            throw APIError.server(page.message ?? "服务器拒绝了这次请求")
        }
        return page
    }

    // MARK: 删除

    func delete(bookIDs: [Int]) async throws -> DeleteResult {
        let url = try endpoint("delete")
        let name = try identity()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            Wire.identity: name,
            "book_ids": bookIDs
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let data: Data
        do {
            let result = try await plainSession.data(for: request)
            data = result.0
        } catch {
            throw APIError.from(error)
        }

        guard let decoded = try? JSONDecoder().decode(DeleteResult.self, from: data) else {
            throw APIError.notOurServer
        }
        guard decoded.success else {
            throw APIError.server(decoded.message ?? "删除失败")
        }
        return decoded
    }

    /// 清除某本书的「失败 / 处理中」记录。
    /// 删除粒度是 (用户名, ISBN)，一次会清掉这本书的全部残留失败行；
    /// 它**绝不删成功记录**，也**完全不碰 Calibre**，所以不需要 book_id。
    func deleteHistory(isbn: String) async throws -> HistoryDeleteResult {
        let url = try endpoint("history").appendingPathComponent("delete")
        let name = try identity()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            Wire.identity: name,
            "isbn": isbn
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let data: Data
        do {
            let result = try await plainSession.data(for: request)
            data = result.0
        } catch {
            throw APIError.from(error)
        }

        guard let decoded = try? JSONDecoder().decode(HistoryDeleteResult.self, from: data) else {
            throw APIError.notOurServer
        }
        guard decoded.success else {
            throw APIError.server(decoded.message ?? "清除记录失败")
        }
        return decoded
    }

    // MARK: 公共

    private func get(_ url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            let result = try await plainSession.data(from: url)
            data = result.0
            response = result.1
        } catch {
            throw APIError.from(error)
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        if status == 401 {
            throw APIError.authRequired
        }

        // 403 几乎总是「用户名不在允许名单」，单独给出去设置的建议。
        if status == 403 {
            let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.message
            throw APIError.notAllowed(message ?? "")
        }

        guard (200..<300).contains(status) else {
            if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
               let message = envelope.message, !message.isEmpty {
                throw APIError.server(message)
            }
            throw APIError.server("请求失败（HTTP \(status)）")
        }

        // 连上了、状态码也对，但返回的不是 JSON —— 多半是把地址填成了网页。
        if let mime = http?.mimeType, !mime.contains("json") {
            throw APIError.notOurServer
        }
        return data
    }
}
