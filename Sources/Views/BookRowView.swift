import SwiftUI

struct BookCoverView: View {
    let book: Book
    var showsTitle: Bool = false

    @State private var image: UIImage?

    private var remoteURL: URL? {
        // 实测 has_cover 不可靠（有记录标 false 但实际能取到图），
        // 所以只要有 book_id 就一直尝试，取不到自然回落到渐变占位。
        guard book.bookID != nil else { return nil }
        return APIClient.shared.coverURL(for: book)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            placeholder

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
                    .overlay(alignment: .leading) {
                        // 薄书脊阴影，让图片也有立体感
                        LinearGradient(
                            colors: [Color.black.opacity(0.22), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 5)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 3)
        .task(id: remoteURL) {
            guard let remoteURL else {
                image = nil
                return
            }
            let loaded = await CoverImageLoader.shared.image(for: remoteURL)
            // 加载不到就保持渐变占位，不显示错误。
            withAnimation(.easeOut(duration: 0.18)) {
                image = loaded
            }
        }
    }

    private var placeholder: some View {
        ZStack(alignment: .topLeading) {
            CoverPalette.gradient(for: book.isbn)

            LinearGradient(
                colors: [Color.black.opacity(0.28), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 6)

            if showsTitle && book.hasMetadata && image == nil {
                Text(book.title ?? "")
                    .font(.system(size: 14.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.941, green: 0.925, blue: 0.882))
                    .lineSpacing(4)
                    .lineLimit(4)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 15)
            }
        }
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
