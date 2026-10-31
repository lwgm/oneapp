import AVFoundation
import SwiftUI
import UIKit

struct ScannerView: View {
    /// 用户点「完成」时回调，带上本次扫描收集到的全部 ISBN（已去重、保持扫描顺序）。
    var onFinish: ([String]) -> Void = { _ in }
    /// 手输直接上传结束后回调，用于让书库刷新。
    var onUploaded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraSession()

    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isTorchOn = false
    @State private var activeSheet: ActiveSheet?
    @State private var showsDiscardConfirm = false

    @State private var scanned: [String] = []

    /// 取景框下方的提示位。三个状态互斥，且都只在有限时间内显示。
    @State private var hint: Hint = .instruction
    @State private var hintToken = UUID()

    private enum Hint: Equatable {
        case instruction
        case added(String)
        case rejected(ISBNValidator.RejectionDetail)
    }

    private enum ActiveSheet: Identifiable {
        case manualInput
        case directUpload(String)

        var id: String {
            switch self {
            case .manualInput: return "manual"
            case .directUpload(let isbn): return "upload-\(isbn)"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch authorization {
            case .authorized:
                liveCamera
            case .notDetermined:
                CameraPrimerView(
                    onAllow: requestAccess,
                    onManualInput: { activeSheet = .manualInput },
                    onClose: close
                )
            default:
                CameraBlockedView(
                    onOpenSettings: openSettings,
                    onManualInput: { activeSheet = .manualInput },
                    onClose: close
                )
            }
        }
        .statusBarHidden(true)
        .onAppear(perform: handleAppear)
        .onDisappear { camera.stop() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .manualInput:
                ManualInputView { isbn in
                    // 手输的书不进 scanned，直接走单本上传。
                    activeSheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        activeSheet = .directUpload(isbn)
                    }
                }
            case .directUpload(let isbn):
                BatchUploadView(isbns: [isbn], autoStart: true) {
                    onUploaded()
                }
            }
        }
        .confirmationDialog(
            "放弃已扫描的 \(scanned.count) 本？",
            isPresented: $showsDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续扫描", role: .cancel) {}
        } message: {
            Text("这些书还没有上传，离开后会丢失。")
        }
    }

    // MARK: - 相机画面

    private var liveCamera: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            topVignette
            bottomVignette

            VStack(spacing: 0) {
                topBar

                Spacer()

                ViewfinderFrame()
                    .padding(.bottom, 22)

                hintArea

                Spacer()

                bottomBar
            }

            if let message = camera.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
            }
        }
    }

    private var topVignette: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.72), location: 0),
                .init(color: .black.opacity(0.18), location: 0.55),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var bottomVignette: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.55), location: 0.55),
                .init(color: .black.opacity(0.88), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 300)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                isTorchOn.toggle()
                camera.setTorch(isTorchOn)
            } label: {
                Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .opacity(camera.isTorchAvailable ? 1 : 0.35)
            .disabled(!camera.isTorchAvailable)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    // MARK: - 提示区

    /// 三种状态高度不同，用固定高度容器兜住，避免取景框随提示上下移动。
    private var hintArea: some View {
        ZStack {
            switch hint {
            case .instruction:
                Text("将书籍背面的条形码置于框内")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.78))
                    .transition(.opacity)

            case .added(let isbn):
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text(isbn)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Text("已加入")
                        .font(.system(size: 12))
                        .opacity(0.72)
                }
                .foregroundStyle(Color(red: 0.60, green: 0.95, blue: 0.78))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(.black.opacity(0.42), in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.94)))

            case .rejected(let detail):
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(Self.message(for: detail.reason))
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    Text(Self.shortened(detail.raw))
                        .font(.system(size: 10.5, design: .monospaced))
                        .opacity(0.6)
                        .lineLimit(1)
                }
                .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.45))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    .black.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
    }

    private static func message(for reason: ISBNValidator.Rejection) -> String {
        switch reason {
        case .notNumeric, .wrongLength:
            return "这不是书籍条码"
        case .notBookPrefix:
            return "这是商品条码，不是书籍"
        case .failedCheckDigit:
            return "条码没读全，请再对准一次"
        }
    }

    private static func shortened(_ raw: String) -> String {
        let limit = 26
        return raw.count <= limit ? raw : String(raw.prefix(limit)) + "…"
    }

    // MARK: - 底部操作

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if scanned.isEmpty {
                Button {
                    activeSheet = .manualInput
                } label: {
                    Text("手动输入 ISBN")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color(white: 0.05))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Button {
                        activeSheet = .manualInput
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 14, weight: .semibold))
                            Text("手动输入")
                                .font(.system(size: 14.5, weight: .medium))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .background(.white.opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onFinish(scanned)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Text("完成")
                                .font(.system(size: 15.5, weight: .semibold))
                            Text("\(scanned.count)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(white: 0.05))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.28), in: Capsule())
                        }
                        .foregroundStyle(Color(white: 0.05))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 38)
    }

    // MARK: - 逻辑

    private func handleAppear() {
        camera.onScan = { outcome in
            switch outcome {
            case .accepted(let isbn):
                add(isbn)
            case .rejected(let detail):
                // 拒绝只在上报时触发一次（相机层已做去重），所以这里可以放心震动。
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showHint(.rejected(detail), for: 2.4)
            }
        }

        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if authorization == .authorized {
            camera.start()
        }
    }

    private func add(_ isbn: String) {
        // 同一本书重复扫到不重复添加，只刷新提示。
        if scanned.contains(isbn) {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            showHint(.added(isbn), for: 2.2)
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        scanned.append(isbn)
        showHint(.added(isbn), for: 2.2)
    }

    /// 提示只在有限时间内显示，之后自动回到引导文案。
    /// 这样「已加入」不会永久占据提示位，警告也不会赖在屏幕上。
    private func showHint(_ newHint: Hint, for seconds: Double) {
        let token = UUID()
        withAnimation(.easeOut(duration: 0.18)) {
            hint = newHint
            hintToken = token
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard hintToken == token else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                hint = .instruction
            }
        }
    }

    private func close() {
        if scanned.isEmpty {
            dismiss()
        } else {
            showsDiscardConfirm = true
        }
    }

    private func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                authorization = granted ? .authorized : .denied
                if granted {
                    camera.start()
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct ViewfinderFrame: View {
    @State private var lineOffset: CGFloat = -68

    private let width: CGFloat = 280
    private let height: CGFloat = 156
    private let cornerLength: CGFloat = 34

    var body: some View {
        ZStack {
            corner(.zero)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            corner(.degrees(90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            corner(.degrees(-90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            corner(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(red: 0.47, green: 0.88, blue: 1.0).opacity(0.95),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .shadow(color: Color(red: 0.35, green: 0.80, blue: 1.0).opacity(0.65), radius: 9)
                .padding(.horizontal, 8)
                .offset(y: lineOffset)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                lineOffset = 68
            }
        }
    }

    private func corner(_ rotation: Angle) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: cornerLength))
            path.addLine(to: CGPoint(x: 0, y: 6))
            path.addQuadCurve(to: CGPoint(x: 6, y: 0), control: .zero)
            path.addLine(to: CGPoint(x: cornerLength, y: 0))
        }
        .stroke(Color.white.opacity(0.94), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .frame(width: cornerLength, height: cornerLength)
        .rotationEffect(rotation)
    }
}

#Preview {
    ScannerView()
}
