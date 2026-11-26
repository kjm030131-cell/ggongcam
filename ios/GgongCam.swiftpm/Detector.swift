import CoreML
import Foundation
import Vision

/// 사이트(ggongcam.pages.dev)와 같은 서버를 쓴다. 모델 파일과 업로드 모두 여기로 간다.
enum Site {
    static let base = URL(string: "https://ggongcam.pages.dev/")!
}

/// 정규화된 박스 (0~1, 왼쪽 위 원점, 세로 화면 기준)
struct Det {
    var rect: CGRect
    var score: Float
    var viaTile: Bool
}

struct IOSModelInfo: Decodable {
    let version: String
    let imgsz: Int
    let conf: Double
    let base: String
    let files: [String]
}

/// 감지 모델 관리: 앱이 켜질 때 사이트의 models/ios.json 을 보고 새 버전이면 받아서 바꾼다.
/// 데이터셋을 바꿔 재학습해도 앱을 다시 설치할 필요가 없다.
@MainActor
final class ModelStore: ObservableObject {
    @Published var status = "모델 확인 중"
    @Published var version: String = UserDefaults.standard.string(forKey: "modelVersion") ?? ""
    @Published var recConf: Float = {
        let v = UserDefaults.standard.double(forKey: "modelConf")
        return v > 0 ? Float(v) : 0.4
    }()
    @Published private(set) var model: VNCoreMLModel?
    @Published var busy = false

    private var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("models", isDirectory: true)
    }

    func loadCached() {
        guard !version.isEmpty else { return }
        let url = dir.appendingPathComponent(version + ".mlmodelc", isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) { open(url) }
    }

    private func open(_ url: URL) {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            let m = try MLModel(contentsOf: url, configuration: cfg)
            let vn = try VNCoreMLModel(for: m)
            // 모델 안의 NMS 가 받는 기준값. 낮게 넘기고 앱에서 감도에 맞춰 다시 거른다.
            vn.featureProvider = Thresholds(iou: 0.45, conf: 0.12)
            model = vn
            status = "준비됨"
        } catch {
            status = "모델을 열지 못했습니다"
        }
    }

    func checkUpdate(force: Bool = false) async {
        if busy { return }
        busy = true
        defer { busy = false }
        do {
            var req = URLRequest(url: Site.base.appendingPathComponent("models/ios.json"))
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: req)
            let info = try JSONDecoder().decode(IOSModelInfo.self, from: data)
            if info.version == version && model != nil && !force {
                status = "준비됨"
                return
            }
            status = "새 모델 받는 중"
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(info.version).mlpackage", isDirectory: true)
            try? FileManager.default.removeItem(at: tmp)
            for f in info.files {
                guard let src = URL(string: info.base + f, relativeTo: Site.base) else { continue }
                let (d, r) = try await URLSession.shared.data(from: src)
                guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let dst = tmp.appendingPathComponent(f)
                try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try d.write(to: dst)
            }
            status = "모델 준비 중"
            let compiled = try await MLModel.compileModel(at: tmp)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let final = dir.appendingPathComponent(info.version + ".mlmodelc", isDirectory: true)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: compiled, to: final)
            try? FileManager.default.removeItem(at: tmp)
            // 예전 모델 지우기
            if let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for u in old where u.lastPathComponent != final.lastPathComponent { try? FileManager.default.removeItem(at: u) }
            }
            version = info.version
            recConf = Float(info.conf)
            UserDefaults.standard.set(info.version, forKey: "modelVersion")
            UserDefaults.standard.set(info.conf, forKey: "modelConf")
            open(final)
            if model != nil { status = "새 모델로 바꿨습니다" }
        } catch {
            status = model == nil ? "모델을 받지 못했습니다. 인터넷을 확인하세요" : "준비됨 (업데이트 확인 실패)"
        }
    }
}

/// CoreML 모델의 NMS 입력(iouThreshold, confidenceThreshold)을 채워 준다.
final class Thresholds: NSObject, MLFeatureProvider {
    let iou: Double, conf: Double
    init(iou: Double, conf: Double) { self.iou = iou; self.conf = conf }
    var featureNames: Set<String> { ["iouThreshold", "confidenceThreshold"] }
    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "iouThreshold": return MLFeatureValue(double: iou)
        case "confidenceThreshold": return MLFeatureValue(double: conf)
        default: return nil
        }
    }
}

/// Vision 으로 감지. 전체 화면 + 화면 조각(세로 2x3) 하나씩 돌아가며 크게 봐서 멀리 있는 작은 꽁초도 잡는다.
final class Detector {
    var model: VNCoreMLModel?
    private var tileIdx = 0

    static let tiles: [CGRect] = {
        let cols = 2, rows = 3, tw: CGFloat = min(1, 1 / CGFloat(cols) * 1.3), th: CGFloat = min(1, 1 / CGFloat(rows) * 1.3)
        var r: [CGRect] = []
        for y in 0..<rows {
            for x in 0..<cols {
                r.append(CGRect(x: CGFloat(x) * (1 - tw) / CGFloat(cols - 1), y: CGFloat(y) * (1 - th) / CGFloat(rows - 1), width: tw, height: th))
            }
        }
        return r
    }()

    /// 이번 프레임에서 본 영역들 (추적기가 '안 보임'을 판단할 때 쓴다)
    private(set) var lastRegions: [(rect: CGRect, tile: Bool)] = []

    func run(_ pb: CVPixelBuffer, conf: Float, precise: Bool) -> [Det] {
        guard let m = model else { return [] }
        var regions: [(rect: CGRect, tile: Bool)] = [(CGRect(x: 0, y: 0, width: 1, height: 1), false)]
        if precise {
            regions.append((Detector.tiles[tileIdx % Detector.tiles.count], true))
            tileIdx += 1
        }
        lastRegions = regions
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
        var reqs: [VNCoreMLRequest] = []
        for g in regions {
            let r = VNCoreMLRequest(model: m)
            r.imageCropAndScaleOption = .scaleFit
            // Vision 의 영역은 왼쪽 아래 원점
            r.regionOfInterest = CGRect(x: g.rect.minX, y: 1 - g.rect.maxY, width: g.rect.width, height: g.rect.height)
            reqs.append(r)
        }
        do { try handler.perform(reqs) } catch { return [] }
        var out: [Det] = []
        for (i, r) in reqs.enumerated() {
            let g = regions[i]
            for case let o as VNRecognizedObjectObservation in r.results ?? [] {
                if o.confidence < conf { continue }
                let b = o.boundingBox   // 영역 안에서 정규화, 왼쪽 아래 원점
                let rect = CGRect(x: g.rect.minX + b.minX * g.rect.width,
                                  y: g.rect.minY + (1 - b.maxY) * g.rect.height,
                                  width: b.width * g.rect.width, height: b.height * g.rect.height)
                out.append(Det(rect: rect, score: o.confidence, viaTile: g.tile))
            }
        }
        return Detector.nms(out)
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        if i.isNull { return 0 }
        let ia = i.width * i.height
        return ia / (a.width * a.height + b.width * b.height - ia + 1e-9)
    }

    /// 겹친 박스 정리. 조각 가장자리에서 잘린 박스가 큰 박스 안에 남지 않게 대부분 포개진 것도 하나로 본다.
    static func nms(_ ds: [Det]) -> [Det] {
        var keep: [Det] = []
        for d in ds.sorted(by: { $0.score > $1.score }) {
            let dup = keep.contains { k in
                let i = k.rect.intersection(d.rect)
                let inter = i.isNull ? 0 : i.width * i.height
                return iou(k.rect, d.rect) > 0.45 || inter / min(k.rect.width * k.rect.height, d.rect.width * d.rect.height) > 0.6
            }
            if !dup { keep.append(d) }
            if keep.count >= 40 { break }
        }
        return keep
    }
}

/// 추적: 프레임 사이 같은 꽁초를 이어 붙이고, 몇 번 연속으로 잡히면 '락온'.
struct Track {
    var id: Int
    var rect: CGRect
    var score: Float
    var hits = 1
    var miss = 0
    var seen: TimeInterval
    var viaTile: Bool
    var lockedAt: TimeInterval? = nil
}

final class Tracker {
    private(set) var tracks: [Track] = []
    private var nextId = 1
    var lockFrames = 4
    /// 이번 업데이트에서 새로 락온된 개수
    private(set) var newLocks = 0

    func reset() { tracks = [] }

    func update(_ dets: [Det], regions: [(rect: CGRect, tile: Bool)], now: TimeInterval) -> [Track] {
        newLocks = 0
        var used = Set<Int>()
        for i in tracks.indices {
            var best = -1
            var bv: CGFloat = 0.25
            for (j, d) in dets.enumerated() where !used.contains(j) {
                let v = Detector.iou(tracks[i].rect, d.rect)
                if v > bv { bv = v; best = j }
            }
            if best >= 0 {
                used.insert(best)
                let d = dets[best], a: CGFloat = 0.6, r = tracks[i].rect
                tracks[i].rect = CGRect(x: r.minX + (d.rect.minX - r.minX) * a, y: r.minY + (d.rect.minY - r.minY) * a,
                                        width: r.width + (d.rect.width - r.width) * a, height: r.height + (d.rect.height - r.height) * a)
                tracks[i].score = d.score
                tracks[i].hits += 1
                tracks[i].miss = 0
                tracks[i].seen = now
                tracks[i].viaTile = d.viaTile
                let need = tracks[i].viaTile ? max(2, lockFrames / 3) : lockFrames
                if tracks[i].lockedAt == nil && tracks[i].hits >= need { tracks[i].lockedAt = now; newLocks += 1 }
            } else {
                // 조각에서만 잡힌 꽁초는 그 조각을 다시 볼 때까지 '안 보임'으로 치지 않는다
                let c = CGPoint(x: tracks[i].rect.midX, y: tracks[i].rect.midY)
                if regions.contains(where: { (!$0.tile && !tracks[i].viaTile) || ($0.tile && $0.rect.contains(c)) }) { tracks[i].miss += 1 }
            }
        }
        for (j, d) in dets.enumerated() where !used.contains(j) {
            tracks.append(Track(id: nextId, rect: d.rect, score: d.score, seen: now, viaTile: d.viaTile))
            nextId += 1
        }
        tracks.removeAll { t in
            t.lockedAt != nil ? (t.miss > 8 || now - t.seen > 3) : (t.miss > 1 || now - t.seen > (t.viaTile ? 2.5 : 0.5))
        }
        return tracks.filter { $0.lockedAt != nil && $0.miss <= 3 }
    }
}
