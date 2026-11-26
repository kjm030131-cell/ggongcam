import AVFoundation
import SwiftUI
import UIKit

/// 뒤 카메라. 렌즈가 여러 개인 아이폰은 가상 카메라(트리플, 듀얼 와이드)를 써서 0.5x(초광각)부터 줌으로 이어서 바꾼다.
final class Camera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "ggongcam.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private(set) var device: AVCaptureDevice?
    /// 카메라 프레임이 올 때마다 영상 큐에서 불린다. 세로(portrait)로 돌려진 프레임이 온다.
    var onFrame: ((CVPixelBuffer) -> Void)?

    @Published var zoom: CGFloat = 1          // 화면에 보이는 배율 (0.5, 1, 2 ...)
    @Published var torchOn = false
    @Published var hasTorch = false
    @Published var hasUltraWide = false
    @Published var bright = false
    @Published var denied = false
    private var wideFactor: CGFloat = 1       // 가상 카메라에서 1x(광각)에 해당하는 videoZoomFactor
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { self.denied = !ok }
                if ok { self.configure() }
            }
        default:
            DispatchQueue.main.async { self.denied = true }
        }
    }

    func resume() { queue.async { if self.configured && !self.session.isRunning { self.session.startRunning() } } }
    func pause() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    private func pickDevice() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        for t in types {
            if let d = AVCaptureDevice.default(t, for: .video, position: .back) { return d }
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func configure() {
        queue.async {
            if self.configured { if !self.session.isRunning { self.session.startRunning() }; return }
            guard let d = self.pickDevice(), let input = try? AVCaptureDeviceInput(device: d) else { return }
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.hd1920x1080) { self.session.sessionPreset = .hd1920x1080 }
            if self.session.canAddInput(input) { self.session.addInput(input) }
            self.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.output.alwaysDiscardsLateVideoFrames = true
            self.output.setSampleBufferDelegate(self, queue: self.queue)
            if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            if let c = self.output.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            self.session.commitConfiguration()

            let ultra = d.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
            let switches = d.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
            self.wideFactor = ultra ? (switches.first ?? 2) : 1
            self.device = d
            if (try? d.lockForConfiguration()) != nil {
                if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
                if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
                d.videoZoomFactor = min(d.activeFormat.videoMaxZoomFactor, max(d.minAvailableVideoZoomFactor, self.wideFactor))
                d.unlockForConfiguration()
            }
            self.configured = true
            self.session.startRunning()
            DispatchQueue.main.async {
                self.hasTorch = d.hasTorch
                self.hasUltraWide = ultra
                self.zoom = 1
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pb)
    }

    var minZoom: CGFloat { hasUltraWide ? 0.5 : 1 }

    /// 화면 배율로 줌. 초광각이 있는 폰은 0.5부터.
    func setZoom(_ z: CGFloat) {
        guard let d = device else { return }
        let wf = wideFactor
        let factor = min(min(d.activeFormat.videoMaxZoomFactor, wf * 10), max(d.minAvailableVideoZoomFactor, max(minZoom, z) * wf))
        zoom = factor / wf
        queue.async {
            if (try? d.lockForConfiguration()) != nil { d.videoZoomFactor = factor; d.unlockForConfiguration() }
        }
    }

    func setTorch(_ on: Bool) {
        guard let d = device, d.hasTorch else { return }
        queue.async {
            if (try? d.lockForConfiguration()) != nil {
                if on, d.isTorchModeSupported(.on) { try? d.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { d.torchMode = .off }
                d.unlockForConfiguration()
            }
            DispatchQueue.main.async { self.torchOn = on && d.torchMode == .on }
        }
    }

    /// 어두울 때 노출을 올린다 (야간 보정).
    func setBright(_ on: Bool) {
        guard let d = device else { return }
        bright = on
        queue.async {
            if (try? d.lockForConfiguration()) != nil {
                d.setExposureTargetBias(on ? min(2.0, d.maxExposureTargetBias) : 0, completionHandler: nil)
                d.unlockForConfiguration()
            }
        }
    }

    /// p: 세로 화면 기준 0~1 좌표(왼쪽 위 원점). 카메라 센서는 가로 기준이라 돌려서 넘긴다.
    func focus(at p: CGPoint) {
        guard let d = device else { return }
        let dp = CGPoint(x: p.y, y: 1 - p.x)
        queue.async {
            if (try? d.lockForConfiguration()) != nil {
                if d.isFocusPointOfInterestSupported { d.focusPointOfInterest = dp; if d.isFocusModeSupported(.autoFocus) { d.focusMode = .autoFocus } }
                if d.isExposurePointOfInterestSupported { d.exposurePointOfInterest = dp; if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure } }
                d.isSubjectAreaChangeMonitoringEnabled = true
                d.unlockForConfiguration()
            }
        }
        // 3초 뒤 다시 자동 초점으로
        queue.asyncAfter(deadline: .now() + 3) {
            if (try? d.lockForConfiguration()) != nil {
                if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
                d.unlockForConfiguration()
            }
        }
    }
}

/// 카메라 미리보기 (화면 꽉 채움)
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        if let c = v.preview.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let c = uiView.preview.connection, c.isVideoRotationAngleSupported(90), c.videoRotationAngle != 90 { c.videoRotationAngle = 90 }
    }
}
