import CoreImage
import Foundation
import UIKit
import Vision

/// 찍은 사진은 앱 안(Documents/pending)에 사진(jpg) + 정보(json) 짝으로 두었다가,
/// 사이트와 같은 업로드 서버(/api/upload)로 보낸다. 인터넷이 끊겨 있으면 쌓아 뒀다가 다음에 보낸다.
struct ShotMeta: Codable {
    var name: String
    var labels: [[Double]]      // [cx, cy, w, h] 0~1
    var split: String           // "train"
    var tags: [String]
    var face: Bool
}

@MainActor
final class ShotStore: ObservableObject {
    @Published var pending = 0
    @Published var blocked = 0           // 얼굴이 보여서 안 보내는 사진
    @Published var sentTotal = UserDefaults.standard.integer(forKey: "sentTotal")
    @Published var note = ""
    @Published var uploading = false

    private var dir: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pending", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    init() { refresh() }

    func refresh() {
        let metas = allMetas()
        pending = metas.filter { !$0.face }.count
        blocked = metas.filter { $0.face }.count
    }

    private func allMetas() -> [ShotMeta] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? JSONDecoder().decode(ShotMeta.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    /// 카메라 큐에서 프레임을 사진으로 바꾼다 (긴 변 1280).
    nonisolated static func render(_ pb: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pb)
        let k = min(1, 1280 / max(ci.extent.width, ci.extent.height))
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: k, y: k))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }

    /// 사진 하나를 저장한다. 사람 얼굴이 크게 보이면 업로드에서 뺀다 (학습 저장소가 공개라서).
    func save(image cg: CGImage, boxes: [CGRect], tags: [String]) -> Bool {
        guard let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.9) else { return false }
        var face = false
        let fr = VNDetectFaceRectanglesRequest()
        if (try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([fr])) != nil {
            face = (fr.results ?? []).contains { $0.confidence > 0.8 && $0.boundingBox.width > 0.05 }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyyMMddHHmmssSSS"
        let name = "ggongcam_" + f.string(from: Date()) + "_ios"
        let labels = boxes.map { b -> [Double] in
            [Double(b.midX), Double(b.midY), Double(b.width), Double(b.height)].map { min(1, max(0, $0)) }
        }
        let meta = ShotMeta(name: name, labels: labels, split: "train", tags: tags, face: face)
        do {
            try jpg.write(to: dir.appendingPathComponent(name + ".jpg"))
            try JSONEncoder().encode(meta).write(to: dir.appendingPathComponent(name + ".json"))
        } catch { return false }
        refresh()
        if face { note = "얼굴이 보이는 사진이라 업로드에서 뺐습니다" }
        return true
    }

    func deleteBlocked() {
        for m in allMetas() where m.face { remove(m.name) }
        refresh()
    }

    private func remove(_ name: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name + ".jpg"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name + ".json"))
    }

    private struct Item: Encodable { let name: String; let jpg: String; let labels: [[Double]]; let split: String; let tags: [String] }
    private struct Body: Encodable { let code: String; let device: String; let items: [Item] }
    private struct Reply: Decodable { let ok: Bool?; let added: Int?; let error: String? }

    func upload(code: String, quiet: Bool = false) async {
        if uploading { return }
        let code = code.trimmingCharacters(in: .whitespaces)
        if code.isEmpty { if !quiet { note = "설정에서 업로드 비밀번호를 먼저 넣으세요" }; return }
        let todo = allMetas().filter { !$0.face }
        if todo.isEmpty { if !quiet { note = blocked > 0 ? "얼굴이 보이는 사진만 남아 있습니다" : "보낼 사진이 없습니다" }; return }
        uploading = true
        defer { uploading = false; refresh() }
        var sent = 0
        do {
            for start in stride(from: 0, to: todo.count, by: 8) {
                let batch = Array(todo[start..<min(todo.count, start + 8)])
                note = "보내는 중 \(sent)/\(todo.count)"
                var items: [Item] = []
                for m in batch {
                    guard let d = try? Data(contentsOf: dir.appendingPathComponent(m.name + ".jpg")) else { continue }
                    items.append(Item(name: m.name, jpg: d.base64EncodedString(), labels: m.labels, split: m.split, tags: m.tags))
                }
                var req = URLRequest(url: Site.base.appendingPathComponent("api/upload"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "content-type")
                req.httpBody = try JSONEncoder().encode(Body(code: code, device: "iPhone 앱", items: items))
                req.timeoutInterval = 60
                let (data, resp) = try await URLSession.shared.data(for: req)
                let r = try? JSONDecoder().decode(Reply.self, from: data)
                guard (resp as? HTTPURLResponse)?.statusCode == 200, r?.ok == true else {
                    throw NSError(domain: "upload", code: 1, userInfo: [NSLocalizedDescriptionKey: r?.error ?? "서버 오류"])
                }
                for m in batch { remove(m.name) }
                sent += batch.count
                sentTotal += batch.count
                UserDefaults.standard.set(sentTotal, forKey: "sentTotal")
            }
            note = "\(sent)장을 보냈습니다. 새벽 2시 학습에 들어갑니다."
        } catch {
            let msg = (error as? URLError) != nil ? "인터넷이 안 돼서 멈췄습니다. 나중에 다시 보냅니다." : error.localizedDescription
            note = (sent > 0 ? "\(sent)장 보낸 뒤 " : "") + msg
        }
    }
}
