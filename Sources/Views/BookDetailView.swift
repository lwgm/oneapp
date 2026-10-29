import SwiftUI

struct BookDetailView: View {
    let book: Book

    private var statusColor: Color {
        if book.status.isFailure {
            return Color(red: 0.75, green: 0.22, blue: 0.17)
        }
        if book.status.isSuccess || book.status == .duplicate {
            return Color(red: 0.141, green: 0.353, blue: 0.325)
        }
        return Color(red: 0.70, green: 0.47, blue: 0.09)
    }

    private var rows: [(String, String, Bool)] {
        var result: [(String, String, Bool)] = [("ISBN", book.isbn, true)]
        if let publisher = book.publisher, !publisher.isEmpty {
            result.append(("出版社", publisher, false))
        }
        if let publishedDate = book.publishedDate, !publishedDate.isEmpty {
            result.append(("出版日期", publishedDate, false))
        }
        if let cost = book.cost, !cost.isEmpty {
            result.append(("处理耗时", cost, true))
        }
        if let createdAt = book.createdAt, !createdAt.isEmpty {
            result.append(("上传时间", createdAt, false))
        }
        if let bookID = book.bookID {
            result.append(("Calibre ID", "\(bookID)", true))
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                metadataCard(rows)

                if book.status.isFailure {
                    noticeCard(
                        title: "这本书没有上传成功",
                        body: "后端抓取或生成 EPUB 失败。可以回到书库重新扫描同一个 ISBN 再试一次。",
                        color: statusColor
                    )
                } else if !book.hasMetadata {
                    noticeCard(
                        title: "书籍信息不完整",
                        body: "后端只返回了 ISBN，没有书名和作者。等抓取成功后重新加载即可显示完整信息。",
                        color: Color(red: 0.70, green: 0.47, blue: 0.09)
                    )
                } else {
                    noticeCard(
                        title: "封面与简介暂未提供",
                        body: "当前接口只返回「是否有封面」的标记，没有封面地址和内容简介。接口补充后这里会自动显示。",
                        color: Color.sub
                    )
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 18) {
            BookCoverView(book: book, showsTitle: true)
                .frame(width: 124, height: 176)

            VStack(alignment: .leading, spacing: 0) {
                Text(book.displayTitle)
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(book.hasMetadata ? Color.ink : Color.sub)
                    .lineSpacing(4)
                    .padding(.bottom, 7)

                Text(book.displayAuthor)
                    .font(
                        book.hasMetadata
                            ? .system(size: 13.5)
                            : .system(size: 12.5, design: .monospaced)
                    )
                    .foregroundStyle(Color.sub)
                    .padding(.bottom, 12)

                if !book.effectiveStatusText.isEmpty {
                    Text(book.effectiveStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            statusColor.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
            }
            .padding(.bottom, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 26)
    }

    private func metadataCard(_ rows: [(String, String, Bool)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                infoRow(
                    row.0,
                    row.1,
                    monospaced: row.2,
                    showsDivider: index < rows.count - 1
                )
            }
        }
        .padding(.horizontal, 16)
        .background(
            Color.white,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.ink.opacity(0.07), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func noticeCard(title: String, body: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(body)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.sub)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            color.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func infoRow(
        _ key: String,
        _ value: String,
        monospaced: Bool = false,
        showsDivider: Bool = true
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(key)
                .font(.system(size: 14))
                .foregroundStyle(Color.sub)
            Spacer(minLength: 8)
            Text(value)
                .font(
                    monospaced
                        ? .system(size: 13, design: .monospaced)
                        : .system(size: 14)
                )
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.ink.opacity(0.055))
                    .frame(height: 1)
            }
        }
    }
}

#Preview("成功") {
    NavigationStack {
        BookDetailView(book: Book.preview())
    }
}

#Preview("失败") {
    NavigationStack {
        BookDetailView(
            book: Book.preview(
                isbn: "9787508698366",
                title: "崔玉涛育儿百科",
                authors: ["崔玉涛"],
                publisher: "中信出版社",
                status: .failed,
                statusText: "上传失败"
            )
        )
    }
}
