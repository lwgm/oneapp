import SwiftUI

/// 批量上传：一次扫描收集到的多本 ISBN，确认后逐本上传。
struct BatchUploadView: View {
    let isbns: [String]
    /// 手输的直接上传场景：跳过确认，进来就开始。
    var autoStart: Bool = false
    /// 全部结束后回调，让书库刷新一次。
    var onFinished: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var items: [Item] = []
    @State private var isRunning = false
    @State private var hasFinished = false

    struct Item: Identifiable {
        let id = UUID()
        let isbn: String
        var requestID = UUID().uuidString
        var state: ItemState = .waiting

        enum ItemState: Equatable {
            case waiting
            case uploading
            case uploaded
            case duplicate(title: String?)
            case timedOut
            case failed(String)
        }

        var isSettled: Bool {
            switch state {
            case .waiting, .uploading: return false
            default: return true
            }
        }

        var isFailure: Bool {
            switch state {
            case .failed, .timedOut: return true
            default: return false
            }
        }
    }

    private var successCount: Int {
        items.filter {
            switch $0.state {
            case .uploaded, .duplicate: return true
            default: return false
            }
        }.count
    }

    private var failureCount: Int { items.filter(\.isFailure).count }

    private var settledCount: Int { items.filter(\.isSettled).count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryRow
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, isLast: index == items.count - 1)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isRunning && item.state == .waiting {
                                    Button(role: .destructive) {
                                        items.removeAll { $0.id == item.id }
                                    } label: {
                                        Label("移除", systemImage: "minus.circle")
                                    }
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isRunning {
                        Button("关闭") { finish() }
                            .font(.system(size: 15))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .interactiveDismissDisabled(isRunning)
        .onAppear {
            guard items.isEmpty else { return }
            items = isbns.map { Item(isbn: $0) }
            if autoStart {
                startUpload()
            }
        }
    }

    private var screenTitle: String {
        if hasFinished { return "上传结果" }
        if isRunning { return "正在上传" }
        return "确认上传"
    }

    // MARK: - 顶部摘要

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            if hasFinished {
                Text(resultHeadline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(resultDetail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sub)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isRunning {
                Text("正在上传 \(settledCount)/\(items.count)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
                Text("逐本上传，每本最长约 50 秒。请保持 App 在前台。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sub)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("共 \(items.count) 本")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("确认后会逐本抓取书籍信息并上传到 Calibre 书库。左滑可以移除不想上传的条目。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sub)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var resultHeadline: String {
        if failureCount == 0 {
            return "全部完成"
        }
        return "成功 \(successCount) 本，失败 \(failureCount) 本"
    }

    private var resultDetail: String {
        if failureCount == 0 {
            return "这些书已经进入你的书单，封面暂未提供，先用色块代替。"
        }
        return "失败的书可以回到书库重新扫描同一个 ISBN 再试一次。"
    }

    // MARK: - 行

    private func row(_ item: Item, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            statusBadge(item.state)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.isbn)
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ink)

                Text(statusText(item.state))
                    .font(.system(size: 11.5))
                    .foregroundStyle(statusColor(item.state))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if case .uploading = item.state {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.ink.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.leading, 62)
            }
        }
    }

    private func statusBadge(_ state: Item.ItemState) -> some View {
        ZStack {
            Circle().fill(statusColor(state).opacity(0.12))
            Image(systemName: statusIcon(state))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(statusColor(state))
        }
        .frame(width: 30, height: 30)
    }

    private func statusIcon(_ state: Item.ItemState) -> String {
        switch state {
        case .waiting: return "clock"
        case .uploading: return "arrow.up"
        case .uploaded, .duplicate: return "checkmark"
        case .timedOut: return "hourglass"
        case .failed: return "exclamationmark"
        }
    }

    private func statusColor(_ state: Item.ItemState) -> Color {
        switch state {
        case .uploaded, .duplicate: return Color(red: 0.141, green: 0.353, blue: 0.325)
        case .timedOut: return Color(red: 0.70, green: 0.47, blue: 0.09)
        case .failed: return Color(red: 0.75, green: 0.22, blue: 0.17)
        default: return Color.sub
        }
    }

    private func statusText(_ state: Item.ItemState) -> String {
        switch state {
        case .waiting: return "等待上传"
        case .uploading: return "正在抓取书籍信息…"
        case .uploaded: return "已上传"
        case .duplicate(let title):
            if let title, !title.isEmpty { return "书单里已有：\(title)" }
            return "书单里已有这本书"
        case .timedOut: return "处理超时，后台可能仍在处理"
        case .failed(let message): return message
        }
    }

    // MARK: - 底部按钮

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 0) {
            if hasFinished {
                Button {
                    finish()
                } label: {
                    Text("完成")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            Color.ink,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)

                if failureCount > 0 {
                    Button {
                        retryFailed()
                    } label: {
                        Text("重试失败的 \(failureCount) 本")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sub)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            } else if isRunning {
                Text("上传中，请勿关闭")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sub)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            } else {
                Button {
                    startUpload()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("开始上传 \(items.count) 本")
                            .font(.system(size: 15.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Color.ink,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)
                .opacity(items.isEmpty ? 0.4 : 1)
                .padding(.horizontal, 18)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color.paper.opacity(0), Color.paper],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - 上传

    private func startUpload() {
        guard !isRunning else { return }
        isRunning = true
        hasFinished = false

        Task { @MainActor in
            await runQueue()

            isRunning = false
            hasFinished = true
            onFinished()
        }
    }

    private func retryFailed() {
        for index in items.indices where items[index].isFailure {
            items[index].state = .waiting
            // 复用原来的 requestID：超时重试服务端按幂等处理，不会重复上传。
        }
        startUpload()
    }

    private func runQueue() async {
        for index in items.indices {
            guard items[index].state == .waiting else { continue }

            items[index].state = .uploading
            let isbn = items[index].isbn
            let requestID = items[index].requestID

            let outcome = await APIClient.shared.upload(
                isbn: isbn,
                requestID: requestID
            )

            switch outcome {
            case .uploaded:
                items[index].state = .uploaded
            case .duplicate(_, let title):
                items[index].state = .duplicate(title: title)
            case .timedOut:
                items[index].state = .timedOut
            case .forbidden(let message), .failed(let message):
                items[index].state = .failed(message)
            }
        }
    }

    private func finish() {
        if !hasFinished {
            onFinished()
        }
        dismiss()
    }
}

#Preview("三本待上传") {
    Color.gray.sheet(isPresented: .constant(true)) {
        BatchUploadView(isbns: ["9787111544937", "9787519821968", "9787111407010"])
    }
}
