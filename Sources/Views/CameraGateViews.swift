import SwiftUI

struct CameraPrimerView: View {
    let onAllow: () -> Void
    let onManualInput: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                closeButton(action: onClose)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            Spacer()

            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.085))
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 86, height: 86)
                .padding(.bottom, 30)

                Text("需要访问相机")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 14)

                Text("用于识别书籍背面的条形码。\n画面只在本机处理，不会上传或保存。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.bottom, 34)

                Button(action: onAllow) {
                    Text("允许使用相机")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(white: 0.04))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onManualInput) {
                    Text("手动输入 ISBN")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .buttonStyle(.plain)
                .padding(.top, 19)
            }
            .padding(.horizontal, 38)

            Spacer()
            Spacer()

            Text("下一步会弹出系统权限请求")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 40)
        }
    }
}

struct CameraBlockedView: View {
    let onOpenSettings: () -> Void
    let onManualInput: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                closeButton(action: onClose)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            Spacer()

            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.085))
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .frame(width: 86, height: 86)
                .padding(.bottom, 30)

                Text("相机权限未开启")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 14)

                Text("需要相机权限才能扫描条形码。\n请在系统设置中允许「书扫」使用相机。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.bottom, 34)

                Button(action: onOpenSettings) {
                    Text("前往设置")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(white: 0.04))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onManualInput) {
                    Text("手动输入 ISBN")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .buttonStyle(.plain)
                .padding(.top, 19)
            }
            .padding(.horizontal, 38)

            Spacer()
            Spacer()
        }
    }
}

private func closeButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "xmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 38, height: 38)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
    }
    .buttonStyle(.plain)
}
