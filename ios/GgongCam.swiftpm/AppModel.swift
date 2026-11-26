import AVFoundation
import Combine
import QuartzCore
import SwiftUI
import UIKit
import Vision

/// 카메라 큐에서만 쓰는 감지 흐름. 결과는 메인 스레드의 AppModel 로 넘긴다.
final class Pipeline {
    let detector = Detector()
    let tracker = Tracker()
    var conf: Float = 0.4
    var precise = true
    var enabled = true
    var lockCapture = false
    var captureRequest = false
    private var lastRun: TimeInterval = 0
    private var lastSeen: TimeInterval = CACurrentMediaTime()
    private var lastLockCap: TimeInterval = 0
    private var shown: [Track] = []
    private var frames = 0
    private var fpsT: TimeInterval = CACurrentMediaTime()
    private var fps: Double = 0
    weak var app: AppModel?

    func handle(_ pb: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        let size = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        // 8초 동안 아무것도 안 보이면 1초에 3번만 감지 (발열, 배터리)
        let sleepy = enabled && now - lastSeen > 8
        var locks = 0
        if !enabled {
            tracker.reset(); shown = []
        } else if detector.model != nil && (!sleepy || now - lastRun > 0.33) {
            lastRun = now
            let dets = detector.run(pb, conf: conf, precise: precise)
            shown = tracker.update(dets, regions: detector.lastRegions, now: now)
            locks = tracker.newLocks
            if !shown.isEmpty { lastSeen = now }
            frames += 1
            if now - fpsT > 1 { fps = Double(frames) / (now - fpsT); frames = 0; fpsT = now }
        }
        var shot: CGImage? = nil
        var manual = false
        if captureRequest {
            captureRequest = false; manual = true
            shot = ShotStore.render(pb)
        } else if lockCapture && locks > 0 && now - lastLockCap > 1.5 {
            lastLockCap = now
            shot = ShotStore.render(pb)
        }
        let tracks = shown, f = fps
        let target = app
        Task { @MainActor in
            target?.receive(tracks: tracks, size: size, locks: locks, shot: shot, manual: manual, sleepy: sleepy, fps: f)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let camera = Camera()
    let models = ModelStore()
    let shots = ShotStore()
    private let pipe = Pipeline()
    private var bag: Set<AnyCancellable> = []

    @Published var boxes: [Track] = []
    @Published var imageSize = CGSize(width: 1080, height: 1920)
    @Published var detecting = true { didSet { let v = detecting, p = pipe; camera.queue.async { p.enabled = v } } }
    @Published var sleeping = false
    @Published var fps: Double = 0
    @Published var toast: String? = nil
    private var toastTask: Task<Void, Never>? = nil

    @Published var uploadCode = UserDefaults.standard.string(forKey: "uploadCode") ?? "" {
        didSet { UserDefaults.standard.set(uploadCode, forKey: "uploadCode") }
    }
    @Published var autoUpload = UserDefaults.standard.bool(forKey: "autoUpload") {
        didSet { UserDefaults.standard.set(autoUpload, forKey: "autoUpload"); if autoUpload { uploadNow(quiet: true) } }
    }
    @Published var lockCapture = UserDefaults.standard.bool(forKey: "lockCapture") {
        didSet { UserDefaults.standard.set(lockCapture, forKey: "lockCapture"); pushSettings() }
    }
    @Published var precise = (UserDefaults.standard.object(forKey: "precise") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(precise, forKey: "precise"); pushSettings() }
    }
    /// 감도: 65 낮음, 50 보통, 35 높음 (웹과 같다. 모델 권장 기준을 50에 맞춘다)
    @Published var sensitivity = (UserDefaults.standard.object(forKey: "sensitivity") as? Int) ?? 50 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity"); pushSettings() }
    }
    @Published var tags: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "tags") ?? []) {
        didSet { UserDefaults.standard.set(Array(tags), forKey: "tags") }
    }

    init() {
        pipe.app = self
        let p = pipe
        camera.onFrame = { pb in p.handle(pb) }
        let q = camera.queue
        models.$model.sink { m in
            q.async { p.detector.model = m; p.tracker.reset() }
        }.store(in: &bag)
        models.$recConf.sink { [weak self] _ in self?.pushSettings() }.store(in: &bag)
        // 하위 객체가 바뀌면 화면도 다시 그린다
        models.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        shots.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        camera.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        pushSettings()
    }

    private func pushSettings() {
        let c = max(0.05, min(0.95, models.recConf * Float(sensitivity) / 50)), pr = precise, lc = lockCapture, p = pipe
        camera.queue.async { p.conf = c; p.precise = pr; p.lockCapture = lc }
    }

    func start() {
        UIApplication.shared.isIdleTimerDisabled = true   // 들고 다닐 때 화면 꺼짐 방지
        camera.start()
        models.loadCached()
        Task { await models.checkUpdate() }
        uploadNow(quiet: true)
    }

    func becameActive() {
        UIApplication.shared.isIdleTimerDisabled = true
        camera.resume()
        Task { await models.checkUpdate() }
        if autoUpload { uploadNow(quiet: true) }
    }

    func wentBackground() {
        camera.setTorch(false)
        camera.pause()
    }

    func receive(tracks: [Track], size: CGSize, locks: Int, shot: CGImage?, manual: Bool, sleepy: Bool, fps: Double) {
        boxes = tracks
        if imageSize != size { imageSize = size }
        if sleeping != sleepy { sleeping = sleepy }
        self.fps = fps
        if locks > 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if let shot {
            let ok = shots.save(image: shot, boxes: tracks.map { $0.rect }, tags: Array(tags))
            if manual { show(ok ? "저장했습니다 (박스 \(tracks.count)개)" : "저장하지 못했습니다"); UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            if !shots.note.isEmpty && shots.note.contains("얼굴") { show(shots.note); shots.note = "" }
            if autoUpload { uploadNow(quiet: true) }
        }
    }

    func capture() { let p = pipe; camera.queue.async { p.captureRequest = true } }

    func uploadNow(quiet: Bool) {
        Task {
            await shots.upload(code: uploadCode, quiet: quiet)
            if !quiet && !shots.note.isEmpty { show(shots.note) }
        }
    }

    func show(_ t: String) {
        toast = t
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(nanoseconds: 1_800_000_000); if !Task.isCancelled { toast = nil } }
    }
}
