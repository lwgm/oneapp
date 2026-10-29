import AVFoundation
import Combine

final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var isTorchAvailable = false
    @Published private(set) var errorMessage: String?

    /// 识别到合法 ISBN 时回调。同一本书持续在画面里时不会反复触发，
    /// 但离开画面后再扫同一本可以再次识别。
    var onCodeDetected: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.lwgm.oneapp.camera.session")
    private var isConfigured = false
    private var videoDevice: AVCaptureDevice?
    private var metadataOutput: AVCaptureMetadataOutput?

    /// 去抖：记录上次识别到的书和时刻，避免同一个条码在画面里被连续重复上报。
    private var lastDetectedCode: String?
    private var lastDetectedAt = Date.distantPast
    private let reDetectionInterval: TimeInterval = 2.5

    func start() {
        lastDetectedCode = nil
        lastDetectedAt = .distantPast

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.configureIfNeeded() else { return }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            let running = self.session.isRunning
            DispatchQueue.main.async { self.isRunning = running }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setTorchNow(false)

            if self.session.isRunning {
                self.session.stopRunning()
            }

            let running = self.session.isRunning
            DispatchQueue.main.async { self.isRunning = running }
        }
    }

    func setTorch(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            self?.setTorchNow(enabled)
        }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            report("找不到可用的后置相机")
            return false
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            report("相机初始化失败")
            return false
        }

        let output = AVCaptureMetadataOutput()

        session.beginConfiguration()
        session.sessionPreset = .high

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            report("相机输入不可用")
            return false
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            report("条码识别不可用")
            return false
        }
        session.addOutput(output)

        session.commitConfiguration()

        // availableMetadataObjectTypes 只有在 output 加入 session 之后才有效，
        // 因此这部分必须放在 commitConfiguration 之后。
        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128]
        let available = output.availableMetadataObjectTypes
        let usable = wanted.filter { available.contains($0) }
        guard !usable.isEmpty else {
            report("设备不支持书籍条码识别")
            return false
        }
        output.metadataObjectTypes = usable
        output.setMetadataObjectsDelegate(self, queue: .main)

        metadataOutput = output
        videoDevice = device
        isConfigured = true

        let torch = device.hasTorch
        DispatchQueue.main.async { self.isTorchAvailable = torch }
        return true
    }

    private func setTorchNow(_ enabled: Bool) {
        guard let device = videoDevice, device.hasTorch else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = enabled ? .on : .off
        device.unlockForConfiguration()
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.errorMessage = message }
    }
}

extension CameraSession: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for object in metadataObjects {
            guard
                let code = object as? AVMetadataMachineReadableCodeObject,
                let value = code.stringValue,
                let isbn = ISBNValidator.normalized(value)
            else { continue }

            let now = Date()
            let isRepeat = (isbn == lastDetectedCode)
                && now.timeIntervalSince(lastDetectedAt) < reDetectionInterval
            guard !isRepeat else { return }

            lastDetectedCode = isbn
            lastDetectedAt = now
            onCodeDetected?(isbn)
            return
        }
    }
}
