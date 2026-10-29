import Foundation

// MARK: - 错误

enum APIError: LocalizedError {
    case notConfigured
    case network(String)
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未配置服务器地址或用户名，请先到设置里填写"
        case .network(let message):
            return "网络连接失败：\(message)"
        case .invalidResponse:
            return "服务器返回了无法识别的内容"
        case .server(let message):
            return message
        }
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
                return .failed("服务器返回了无法识别的内容")
            }
            guard check.success else {
                return .failed(check.message ?? "服务器拒绝了这次请求")
            }
            if check.allowed == true {
                return .allowed(check.message ?? "已开通")
            }
            return .denied(check.message ?? "功能暂时没开通")
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
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
            return .failed(error.localizedDescription)
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
            throw APIError.invalidResponse
        }

        let data = try await get(url)
        guard let page = try? JSONDecoder().decode(HistoryPage.self, from: data) else {
            throw APIError.invalidResponse
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
            throw APIError.network(error.localizedDescription)
        }

        guard let decoded = try? JSONDecoder().decode(DeleteResult.self, from: data) else {
            throw APIError.invalidResponse
        }
        guard decoded.success else {
            throw APIError.server(decoded.message ?? "删除失败")
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
            throw APIError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            throw APIError.server("接口需要认证，请检查服务端配置")
        }
        guard (200..<300).contains(status) else {
            // 业务失败也常以 200 返回，走到这里通常是网关或路径问题。
            if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
               let message = envelope.message, !message.isEmpty {
                throw APIError.server(message)
            }
            throw APIError.server("请求失败（HTTP \(status)）")
        }
        return data
    }
}
