import Foundation

enum UploadStatus: String, Decodable {
    case success
    case duplicate
    case failed
    case pending
    case unknown

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = UploadStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .success: return "已上传"
        case .duplicate: return "库中已有"
        case .failed: return "上传失败"
        case .pending: return "处理中"
        case .unknown: return ""
        }
    }

    /// 只有真正上传成功才用主色；失败用红色，其余用次级灰。
    var isSuccess: Bool { self == .success }
    var isFailure: Bool { self == .failed }
}

struct Book: Identifiable, Hashable, Decodable {
    let id: Int
    let isbn: String
    let title: String?
    let authors: [String]
    let publisher: String?
    let publishedDate: String?
    let status: UploadStatus
    let success: Bool
    let statusText: String
    let bookID: Int?
    let hasCover: Bool
    let cost: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, isbn, title, authors, publisher, status, success, cost
        case publishedDate = "published_date"
        case statusText = "status_text"
        case bookID = "book_id"
        case hasCover = "has_cover"
        case createdAt = "created_at"
    }

    init(
        id: Int,
        isbn: String,
        title: String? = nil,
        authors: [String] = [],
        publisher: String? = nil,
        publishedDate: String? = nil,
        status: UploadStatus = .success,
        success: Bool = true,
        statusText: String = "",
        bookID: Int? = nil,
        hasCover: Bool = false,
        cost: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.isbn = isbn
        self.title = title
        self.authors = authors
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.status = status
        self.success = success
        self.statusText = statusText
        self.bookID = bookID
        self.hasCover = hasCover
        self.cost = cost
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
        authors = Book.decodeAuthors(from: container)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        publishedDate = try container.decodeIfPresent(String.self, forKey: .publishedDate)
        status = (try? container.decode(UploadStatus.self, forKey: .status)) ?? .unknown
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText) ?? ""
        bookID = try container.decodeIfPresent(Int.self, forKey: .bookID)
        hasCover = try container.decodeIfPresent(Bool.self, forKey: .hasCover) ?? false
        cost = try container.decodeIfPresent(String.self, forKey: .cost)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    /// 文档约定 authors 是字符串数组，但为了不被单字符串噎住，这里两种都接受。
    private static func decodeAuthors(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [String] {
        if let list = try? container.decodeIfPresent([String].self, forKey: .authors) {
            return list.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        if let single = try? container.decodeIfPresent(String.self, forKey: .authors) {
            return single
                .split(whereSeparator: { $0 == "," || $0 == "/" || $0 == "，" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        return "书籍信息待补充"
    }

    var displayAuthor: String {
        if !authors.isEmpty { return authors.joined(separator: " · ") }
        return "ISBN \(isbn)"
    }

    var hasMetadata: Bool {
        guard let title else { return false }
        return !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 后端只返回 has_cover 布尔值，没有封面 URL，因此一律使用渐变占位。
    var effectiveStatusText: String {
        statusText.isEmpty ? status.label : statusText
    }
}

extension Book {
    static func preview(
        isbn: String = "9787111544937",
        title: String? = "深入理解计算机系统",
        authors: [String] = ["Randal E. Bryant"],
        publisher: String? = "机械工业出版社",
        status: UploadStatus = .success,
        statusText: String = "已上传"
    ) -> Book {
        Book(
            id: abs(isbn.hashValue % 100_000),
            isbn: isbn,
            title: title,
            authors: authors,
            publisher: publisher,
            publishedDate: "2016-11",
            status: status,
            success: status == .success,
            statusText: statusText,
            bookID: 42,
            hasCover: true,
            cost: "23.4s",
            createdAt: "2026-10-29 12:40:11"
        )
    }
}
