import AVFoundation
import Combine

final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var isTorchAvailable = false
    @Published private(set) var errorMessage: String?

    /// 一次识别结果：可能是合法 ISBN，也可能是被拒的条码。
    /// 被拒时同样会回调，好让界面告诉用户「读到了东西，但不是书」。
    var onScan: ((ISBNValidator.Outcome) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.lwgm.oneapp.camera.session")
    private var isConfigured = false
    private var videoDevice: AVCaptureDevice?
    private var metadataOutput: AVCaptureMetadataOutput?

    /// 稳定过滤：条码要在画面里连续停留这么久才算「用户对着它」。
    /// 扫书架时隔壁书的条码快速掠过不会触发提示。
    private var candidateValue: String?
    private var candidateSince = Date.distantPast
    private let candidateHoldInterval: TimeInterval = 0.30

    /// 同一个读数在这段时间内不重复上报。
    private var lastEmittedValue: String?
    private var lastEmittedAt = Date.distantPast
    private let reEmitInterval: TimeInterval = 2.5

    func start() {
        resetDetectionState()

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
        guard
            let object = metadataObjects.first(where: {
                $0 is AVMetadataMachineReadableCodeObject
            }) as? AVMetadataMachineReadableCodeObject,
            let value = object.stringValue,
            !value.isEmpty
        else { return }

        let now = Date()

        // 读数一变就重置计时，交替出现的两个码永远不会「稳定」。
        if value != candidateValue {
            candidateValue = value
            candidateSince = now
        }
        guard now.timeIntervalSince(candidateSince) >= candidateHoldInterval else {
            return
        }

        if value == lastEmittedValue, now.timeIntervalSince(lastEmittedAt) < reEmitInterval {
            return
        }
        lastEmittedValue = value
        lastEmittedAt = now

        onScan?(ISBNValidator.classify(value))
    }
}

extension CameraSession {
    private func resetDetectionState() {
        candidateValue = nil
        candidateSince = .distantPast
        lastEmittedValue = nil
        lastEmittedAt = .distantPast
    }
}
