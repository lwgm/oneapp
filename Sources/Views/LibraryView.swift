import SwiftUI

struct LibraryView: View {
    @StateObject private var store = LibraryStore()
    @ObservedObject private var settings = AppSettings.shared

    @State private var searchText = ""
    @State private var isScannerPresented = false
    @State private var path = NavigationPath()
    @State private var activeSheet: ActiveSheet?
    @State private var deleteTarget: Book?
    @State private var banner: Banner?

    private struct Banner: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private enum ActiveSheet: Identifiable {
        case batch([String])

        var id: String {
            switch self {
            case .batch(let isbns): return "batch-" + isbns.joined(separator: ",")
            }
        }
    }

    private enum Route: Hashable {
        case book(Book)
        case settings
    }

    private var filteredBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.books }
        return store.books.filter { book in
            book.isbn.contains(query)
                || (book.title?.localizedCaseInsensitiveContains(query) ?? false)
                || book.authors.contains { $0.localizedCaseInsensitiveContains(query) }
                || (book.publisher?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Color.paper.ignoresSafeArea())
                .navigationTitle("书库")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            path.append(Route.settings)
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(Color.sub)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if settings.isConfigured {
                        scanButton
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .book(let book):
                        BookDetailView(book: book) {
                            Task { await store.refresh() }
                        }
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .tint(Color.ink)
        .task { await store.loadInitialIfNeeded() }
        .onChange(of: settings.serverAddress) { _, _ in reloadAfterSettingsChange() }
        .onChange(of: settings.username) { _, _ in reloadAfterSettingsChange() }
        .fullScreenCover(isPresented: $isScannerPresented) {
            ScannerView(
                onFinish: { isbns in
                    guard !isbns.isEmpty else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        activeSheet = .batch(isbns)
                    }
                },
                onUploaded: {
                    Task { await store.refresh() }
                }
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .batch(let isbns):
                BatchUploadView(isbns: isbns) {
                    Task { await store.refresh() }
                }
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = deleteTarget {
                Button(deleteActionTitle, role: .destructive) {
                    let book = target
                    deleteTarget = nil
                    performDelete(book)
                }
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteExplanation)
        }
        .alert(
            banner?.text ?? "",
            isPresented: Binding(
                get: { banner != nil },
                set: { if !$0 { banner = nil } }
            )
        ) {
            Button("好", role: .cancel) { banner = nil }
        }
    }

    /// 配置变了意味着换了身份，旧书单属于上一个用户名，继续显示会误导。
    /// 所以先清空再加载，结果与冷启动一致。
    private func reloadAfterSettingsChange() {
        Task { await store.reloadForNewIdentity() }
    }

    private var deleteTitle: String {
        guard let deleteTarget else { return "删除这本书？" }
        if deleteTarget.success {
            return "删除「\(deleteTarget.displayTitle)」？"
        }
        return "清除「\(deleteTarget.displayTitle)」的失败记录？"
    }

    private var deleteActionTitle: String {
        guard let deleteTarget else { return "删除" }
        return deleteTarget.success ? "删除" : "清除记录"
    }

    private var deleteExplanation: String {
        guard let deleteTarget else { return "" }
        if deleteTarget.success {
            return "会从你的书单移除，并从 Calibre 库中删除。删除后这个 ISBN 可以重新上传。"
        }
        return "只清掉这条上传记录，不会影响 Calibre 里的任何书。之后可以重新扫描或重试上传。"
    }

    private func performDelete(_ book: Book) {
        Task {
            if let message = await store.delete(book) {
                banner = Banner(text: message, isError: true)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !settings.isConfigured {
            ScrollView {
                SetupPromptView {
                    path.append(Route.settings)
                }
                .frame(minHeight: 460)
            }
        } else if store.books.isEmpty {
            ScrollView {
                Group {
                    if !store.hasLoadedOnce {
                        // 用一个可伸缩的容器吸收高度提案。
                        // 直接把 .frame(minHeight:) 压在 ProgressView 上，
                        // iOS 26 会把它那层玻璃底衬垂直拉成一条整屏光带。
                        ZStack {
                            Color.clear
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 460)
                    } else if let loadError = store.loadError {
                        LibraryErrorView(
                            error: loadError,
                            onRetry: { Task { await store.refresh() } },
                            onOpenSettings: { path.append(Route.settings) }
                        )
                        .frame(minHeight: 460)
                    } else {
                        EmptyLibraryView()
                            .frame(minHeight: 460)
                    }
                }
            }
            .refreshable { await store.refresh() }
        } else {
            bookList
        }
    }

    private var bookList: some View {
        List {
            if let loadError = store.loadError {
                inlineError(loadError.message)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            searchField
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 14, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ForEach(Array(filteredBooks.enumerated()), id: \.element.id) { index, book in
                Button {
                    path.append(Route.book(book))
                } label: {
                    BookRowView(
                        book: book,
                        showsDivider: index < filteredBooks.count - 1
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget = book
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .task {
                    await store.loadMoreIfNeeded(currentBook: book)
                }
            }

            Group {
                if store.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 6)
                } else if !filteredBooks.isEmpty && !store.hasMore {
                    Text("共 \(store.total) 本")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sub.opacity(0.55))
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh() }
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
            Text(message)
                .font(.system(size: 12.5))
                .lineLimit(2)
            Spacer(minLength: 6)
            Button("重试") {
                Task { await store.refresh() }
            }
            .font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(Color(red: 0.62, green: 0.24, blue: 0.19))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Color(red: 0.75, green: 0.22, blue: 0.17).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sub.opacity(0.75))

            TextField("搜索书名、作者或 ISBN", text: $searchText)
                .font(.system(size: 14.5))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sub.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 40)
        .background(
            Color.ink.opacity(0.062),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
    }

    private var scanButton: some View {
        Button {
            isScannerPresented = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                Text("扫描一本书")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Color.ink,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                colors: [Color.paper.opacity(0), Color.paper],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions
}

// MARK: - 空态 / 错误态

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            BookStack()
                .frame(width: 104, height: 122)
                .padding(.bottom, 30)

            Text("书库还是空的")
                .font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 11)

            Text("把书翻到背面，对准条形码\n确认后即可收录进你的 Calibre 书库")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.sub)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct SetupPromptView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.sub.opacity(0.5))
                .padding(.bottom, 20)

            Text("还没连接服务器")
                .font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 11)

            Text("填写后端地址和用户名后，\n这里会显示你的书单")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.sub)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, 26)

            Button(action: onOpenSettings) {
                Text("去设置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 34)
                    .frame(height: 46)
                    .background(
                        Color.ink,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct LibraryErrorView: View {
    let error: LoadError
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    /// 配置类问题给「去设置」，网络类问题给「重试」。
    private var icon: String {
        error.suggestsSettings ? "gearshape" : "wifi.exclamationmark"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.sub.opacity(0.55))
                .padding(.bottom, 20)

            Text(error.title)
                .font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 10)

            Text(error.message)
                .font(.system(size: 13))
                .foregroundStyle(Color.sub)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)

            Button {
                error.suggestsSettings ? onOpenSettings() : onRetry()
            } label: {
                Text(error.suggestsSettings ? "去设置" : "重试")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 34)
                    .frame(height: 46)
                    .background(
                        Color.ink,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.plain)

            if error.suggestsSettings {
                Button(action: onRetry) {
                    Text("重新加载")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sub)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct BookStack: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.ink.opacity(0.1), lineWidth: 1)
                )
                .frame(width: 62, height: 84)
                .rotationEffect(.degrees(-10))
                .offset(x: -19, y: 10)
                .opacity(0.5)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.ink.opacity(0.1), lineWidth: 1)
                )
                .frame(width: 62, height: 84)
                .rotationEffect(.degrees(9))
                .offset(x: 19, y: 6)
                .opacity(0.72)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(CoverPalette.gradient(for: "书"))
                .frame(width: 64, height: 92)
                .shadow(color: Color.black.opacity(0.22), radius: 15, x: 0, y: 10)
        }
    }
}

#Preview {
    LibraryView()
}
