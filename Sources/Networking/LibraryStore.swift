import Foundation
import Combine

final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?

    private var nextBeforeID: Int?
    private var didLoadOnce = false
    private let pageSize = 30

    var isEmpty: Bool { books.isEmpty }

    /// 首次进入时调用；已经加载过就不再重复拉取。
    func loadInitialIfNeeded() async {
        guard !didLoadOnce else { return }
        didLoadOnce = true
        isLoading = true
        await reload()
        isLoading = false
    }

    /// 下拉刷新与上传完成后调用，保持当前列表直到新数据到达。
    func refresh() async {
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
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
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
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
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

    /// 从书库移除一条记录。成功后直接刷新列表，保证与后端一致。
    func delete(_ book: Book) async -> String? {
        guard let bookID = book.bookID else {
            return "这条记录没有 book_id，无法通过接口删除"
        }

        do {
            let result = try await APIClient.shared.delete(bookIDs: [bookID])

            // 先本地移除，界面立即响应；随后再拉一次以保证分页与总数一致。
            books.removeAll { $0.id == book.id }
            total = max(0, total - 1)

            await reload()
            return result.wasKeptInLibrary ? "已从你的书单移除（库中仍有其他用户）" : nil
        } catch {
            return (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
