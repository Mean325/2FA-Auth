import AppKit
import AVFoundation
import CoreMedia
import SwiftUI
import TwoFACore

struct CameraScanPanel: View {
    @Environment(\.palette) private var palette
    @State private var scanner = CameraScanModel()
    var onCancel: () -> Void
    var onScan: (String) -> Bool

    var body: some View {
        PaperPanel(width: 480) {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "camera")
                    Text(L10n.text(L10nKey.cameraScan)).font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(palette.text)
                ZStack {
                    Color.black
                    if scanner.phase == .running {
                        CameraPreview(session: scanner.capture.session)
                        Image(systemName: "viewfinder")
                            .font(.system(size: 120, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.85))
                            .allowsHitTesting(false)
                    } else {
                        VStack(spacing: 12) {
                            if scanner.phase == .requesting {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: scanner.phase == .denied ? "camera.badge.ellipsis" : "camera")
                                    .font(.system(size: 30))
                            }
                            Text(L10n.text(scanner.phase.messageKey))
                                .font(.system(size: 13))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            if scanner.phase == .denied {
                                Button(L10n.text(L10nKey.cameraOpenSettings)) { openCameraSettings() }
                                    .modifier(SettingsGlassButton())
                            } else if scanner.phase != .requesting {
                                Button(L10n.text(L10nKey.storageRetry)) { scanner.start(onScan: onScan) }
                                    .modifier(SettingsGlassButton())
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(L10n.text(L10nKey.cameraPreview))
                Text(L10n.text(scanner.invalidCode ? L10nKey.cameraInvalidCode : L10nKey.cameraScanHint))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    QuietButton(title: L10n.text(L10nKey.actionCancel)) {
                        scanner.stop()
                        onCancel()
                    }
                }
            }
            .padding(20)
        }
        .onAppear { scanner.start(onScan: onScan) }
        .onDisappear { scanner.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if scanner.phase == .denied { scanner.start(onScan: onScan) }
        }
        .onExitCommand { scanner.stop(); onCancel() }
    }

    private func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum CameraPhase: Sendable {
    case requesting, running, denied, unavailable, failed

    var messageKey: String {
        switch self {
        case .requesting: return L10nKey.cameraRequesting
        case .running: return L10nKey.cameraScanHint
        case .denied: return L10nKey.cameraDenied
        case .unavailable: return L10nKey.cameraUnavailable
        case .failed: return L10nKey.cameraFailed
        }
    }
}

@MainActor
@Observable
private final class CameraScanModel {
    var phase = CameraPhase.requesting
    var invalidCode = false
    private var active = false
    private var onScan: ((String) -> Bool)?
    @ObservationIgnored lazy var capture = CameraCapture(
        onPhase: { [weak self] phase in
            Task { @MainActor in
                guard let self, self.active else { return }
                self.phase = phase
                if phase != .running { self.active = false }
            }
        },
        onPayload: { [weak self] payload in
            Task { @MainActor in
                guard let self, self.active else { return }
                if self.onScan?(payload) == true { self.stop() }
                else { self.invalidCode = true }
            }
        }
    )

    func start(onScan: @escaping (String) -> Bool) {
        guard !active else { return }
        active = true
        self.onScan = onScan
        phase = .requesting
        invalidCode = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: capture.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.active else { return }
                    if granted { self.capture.start() }
                    else { self.phase = .denied; self.active = false }
                }
            }
        default: phase = .denied; active = false
        }
    }

    func stop() {
        active = false
        capture.stop()
    }
}

/// 会话生命周期与逐帧识别分开排队，停止会话时不会阻塞采集回调。
private final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let onPhase: @Sendable (CameraPhase) -> Void
    private let onPayload: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "app.2famac.camera", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "app.2famac.camera.frames", qos: .userInitiated)
    private var output: AVCaptureVideoDataOutput?
    private var lastRead = 0.0
    private var lastPayloads: Set<String> = []
    private var runtimeObserver: NSObjectProtocol?

    init(onPhase: @escaping @Sendable (CameraPhase) -> Void, onPayload: @escaping @Sendable (String) -> Void) {
        self.onPhase = onPhase
        self.onPayload = onPayload
        super.init()
    }

    func start() {
        queue.async { [self] in
            stopSession()
            guard let device = AVCaptureDevice.default(for: .video) else {
                onPhase(.unavailable)
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                session.beginConfiguration()
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    onPhase(.failed)
                    return
                }
                session.addInput(input)
                guard session.canAddOutput(output) else {
                    session.removeInput(input)
                    session.commitConfiguration()
                    onPhase(.failed)
                    return
                }
                if session.canSetSessionPreset(.hd1920x1080) {
                    session.sessionPreset = .hd1920x1080
                } else if session.canSetSessionPreset(.high) {
                    session.sessionPreset = .high
                }
                session.addOutput(output)
                output.setSampleBufferDelegate(self, queue: frameQueue)
                self.output = output
                session.commitConfiguration()
                configureForScanning(device)
                runtimeObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] _ in
                    guard let self else { return }
                    self.queue.async {
                        self.stopSession()
                        self.onPhase(.failed)
                    }
                }
                session.startRunning()
                if session.isRunning { onPhase(.running) }
                else { stopSession(); onPhase(.failed) }
            } catch {
                stopSession()
                onPhase(.failed)
            }
        }
    }

    func stop() { queue.async { [self] in stopSession() } }

    private func configureForScanning(_ device: AVCaptureDevice) {
        // 部分摄像头没有可调焦镜头，按能力设置，保留它们的采集能力。
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        } catch {
            // 设备暂时不允许调参时，仍可使用默认参数扫码。
        }
    }

    private func stopSession() {
        if let runtimeObserver { NotificationCenter.default.removeObserver(runtimeObserver) }
        runtimeObserver = nil
        output?.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        output = nil
        frameQueue.sync {
            lastRead = 0
            lastPayloads = []
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRead >= 0.1, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRead = now
        let payloads = QRCodeReader.payloads(in: buffer)
        let fresh = Set(payloads).subtracting(lastPayloads)
        lastPayloads = Set(payloads)
        for payload in payloads where fresh.contains(payload) { onPayload(payload) }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ view: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        private let preview: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}
