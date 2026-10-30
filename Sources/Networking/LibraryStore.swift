import Foundation
import Combine

final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var total = 0
    /// 是否已经完成过一次加载尝试（成功或失败都算）。
    /// 首帧用它挡住空态，避免在数据到达前闪现一次「书库还是空的」。
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    /// 结构化错误：错误页需要知道「该重试还是该去设置」。
    @Published private(set) var loadError: LoadError?

    private var nextBeforeID: Int?
    private var didLoadOnce = false
    private let pageSize = 30

    var isEmpty: Bool { books.isEmpty }

    /// 首次进入时调用；已经加载过就不再重复拉取。
    func loadInitialIfNeeded() async {
        guard !didLoadOnce else { return }
        didLoadOnce = true
        await reload()
    }

    /// 下拉刷新与上传完成后调用，保持当前列表直到新数据到达。
    ///
    /// 失败时不清空列表是有意为之：网络抖动不该让你丢掉正在看的内容。
    func refresh() async {
        await reload()
    }

    /// 服务器地址或用户名变了。
    ///
    /// 已有的书单属于旧身份，继续显示会造成误导（比如「用户名没权限」的
    /// 错误条下面还挂着上一个用户名抓到的书）。所以这里先清空再重新加载，
    /// 让结果与冷启动完全一致。
    func reloadForNewIdentity() async {
        books = []
        total = 0
        hasMore = false
        nextBeforeID = nil
        loadError = nil
        hasLoadedOnce = false
        didLoadOnce = true
        await reload()
    }

    func loadMoreIfNeeded(currentBook: Book) async {
        guard hasMore, !isLoadingMore else { return }
        guard books.last?.id == currentBook.id else { return }
        guard let beforeID = nextBeforeID else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await APIClient.shared.fetchHistory(
                limit: pageSize,
                beforeID: beforeID
            )
            append(page)
            loadError = nil
        } catch {
            loadError = .init(Self.apiError(from: error))
        }
    }

    /// 把任意错误收敛到 `APIError`，避免各层各自拼文案。
    private static func apiError(from error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }
        return APIError.from(error)
    }

    private func reload() async {
        do {
            let page = try await APIClient.shared.fetchHistory(
                limit: pageSize,
                beforeID: nil
            )
            books = page.items
            total = page.total ?? page.items.count
            hasMore = page.hasMore ?? false
            nextBeforeID = page.nextBeforeID
            loadError = nil
            hasLoadedOnce = true
        } catch {
            loadError = .init(Self.apiError(from: error))
            // 失败也算尝试过，否则会一直停在加载态而看不到错误。
            hasLoadedOnce = true
        }
    }

    private func append(_ page: HistoryPage) {
        let existing = Set(books.map(\.id))
        books.append(contentsOf: page.items.filter { !existing.contains($0.id) })
        total = page.total ?? total
        hasMore = page.hasMore ?? false
        nextBeforeID = page.nextBeforeID
    }

    // MARK: - 删除

    /// 从书库移除一条记录。
    ///
    /// 两类记录走两个完全不同的接口：
    /// - `success == true`（书已在书单里）→ `/delete`，需要 `book_id`，**会真的删 Calibre 里的书**
    /// - `success == false`（失败 / 处理中，只是上传日志）→ `/history/delete`，按 ISBN 清记录，
    ///   **完全不碰 Calibre**，也不需要 `book_id`
    func delete(_ book: Book) async -> String? {
        if book.success {
            return await deleteFromLibrary(book)
        }
        return await deleteHistoryRecord(book)
    }

    private func deleteFromLibrary(_ book: Book) async -> String? {
        guard let bookID = book.bookID else {
            return "这条记录缺少 book_id，无法从库中删除"
        }

        do {
            let result = try await APIClient.shared.delete(bookIDs: [bookID])

            // 先本地移除，界面立即响应；随后再拉一次以保证分页与总数一致。
            books.removeAll { $0.id == book.id }
            total = max(0, total - 1)

            await reload()
            return result.wasKeptInLibrary ? "已从你的书单移除（库中仍有其他用户）" : nil
        } catch {
            return Self.apiError(from: error).errorDescription ?? "删除失败"
        }
    }

    private func deleteHistoryRecord(_ book: Book) async -> String? {
        do {
            _ = try await APIClient.shared.deleteHistory(isbn: book.isbn)

            books.removeAll { $0.id == book.id }
            total = max(0, total - 1)

            await reload()
            return nil
        } catch {
            return Self.apiError(from: error).errorDescription ?? "清除记录失败"
        }
    }
}
