import SwiftUI

struct BookCoverView: View {
    let book: Book
    var showsTitle: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            CoverPalette.gradient(for: book.isbn)

            LinearGradient(
                colors: [Color.black.opacity(0.28), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 6)

            if showsTitle && book.hasMetadata {
                Text(book.title ?? "")
                    .font(.system(size: 14.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.941, green: 0.925, blue: 0.882))
                    .lineSpacing(4)
                    .lineLimit(4)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 15)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 3)
    }
}

struct BookRowView: View {
    let book: Book
    var showsDivider: Bool = false

    private var statusColor: Color {
        if book.status.isFailure {
            return Color(red: 0.75, green: 0.22, blue: 0.17)
        }
        if book.status.isSuccess || book.status == .duplicate {
            return Color(red: 0.141, green: 0.353, blue: 0.325)
        }
        return Color(red: 0.70, green: 0.47, blue: 0.09)
    }

    var body: some View {
        HStack(spacing: 13) {
            BookCoverView(book: book)
                .frame(width: 46, height: 65)

            VStack(alignment: .leading, spacing: 0) {
                Text(book.displayTitle)
                    .font(.system(size: 14.5, weight: .semibold, design: .serif))
                    .foregroundStyle(book.hasMetadata ? Color.ink : Color.sub)
                    .lineLimit(1)
                    .padding(.bottom, 4)

                Text(book.displayAuthor)
                    .font(
                        book.hasMetadata
                            ? .system(size: 12.5)
                            : .system(size: 11.5, design: .monospaced)
                    )
                    .foregroundStyle(Color.sub)
                    .lineLimit(1)
                    .padding(.bottom, 3)

                HStack(spacing: 6) {
                    Text(book.isbn)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.sub.opacity(0.5))

                    if !book.status.isSuccess && !book.effectiveStatusText.isEmpty {
                        Text(book.effectiveStatusText)
                            .font(.system(size: 10))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                statusColor.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                    }
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sub.opacity(0.25))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.ink.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.leading, 67)
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        BookRowView(book: Book.preview(), showsDivider: true)
        BookRowView(
            book: Book.preview(
                isbn: "9787508698366",
                title: "崔玉涛育儿百科",
                authors: ["崔玉涛"],
                publisher: "中信出版社",
                status: .failed,
                statusText: "上传失败"
            ),
            showsDivider: true
        )
        BookRowView(book: Book.preview(isbn: "9787115216878", title: nil, authors: []))
    }
    .background(Color.paper)
}
