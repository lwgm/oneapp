import SwiftUI

struct ManualInputView: View {
    /// 校验通过的 ISBN，交给调用方直接上传。
    var onSubmit: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    /// 与扫码走完全相同的校验：位数、校验位、978/979 前缀。
    private var validated: String? {
        ISBNValidator.normalized(text)
    }

    private var isTooLong: Bool {
        let digits = text.filter { $0.isNumber || $0 == "X" || $0 == "x" }
        return digits.count > 13
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("扫不出来时用这里，确认后直接上传到书库。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sub)
                    .lineSpacing(4)
                    .padding(.bottom, 22)

                HStack(spacing: 10) {
                    TextField("9787111544937", text: $text)
                        .font(.system(size: 16, design: .monospaced))
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 1.5)
                        )

                    Button {
                        guard let isbn = validated else { return }
                        dismiss()
                        onSubmit(isbn)
                    } label: {
                        Text("上传")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 50)
                            .background(
                                Color.accentColor.opacity(validated == nil ? 0.35 : 1),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(validated == nil)
                }
                .padding(.bottom, 12)

                hint

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .background(Color(red: 0.969, green: 0.969, blue: 0.976).ignoresSafeArea())
            .navigationTitle("手动输入 ISBN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .font(.system(size: 15))
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .onAppear { isFocused = true }
    }

    private var borderColor: Color {
        if validated != nil { return Color.ink.opacity(0.14) }
        if text.isEmpty { return Color.ink.opacity(0.14) }
        return Color(red: 0.75, green: 0.22, blue: 0.17).opacity(0.55)
    }

    @ViewBuilder
    private var hint: some View {
        if let isbn = validated {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                Text("将上传 \(isbn)")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Color(red: 0.141, green: 0.353, blue: 0.325))
        } else if text.isEmpty {
            Text("支持 ISBN-10（10 位）与 ISBN-13（13 位），自动忽略连字符")
                .font(.system(size: 12))
                .foregroundStyle(Color.sub.opacity(0.7))
        } else if isTooLong {
            Text("位数超出，ISBN 最长 13 位")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.75, green: 0.22, blue: 0.17))
        } else {
            Text("还不能上传：位数或校验位不对，请核对书背面的号码")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.75, green: 0.22, blue: 0.17))
        }
    }
}

#Preview {
    ManualInputView()
}
