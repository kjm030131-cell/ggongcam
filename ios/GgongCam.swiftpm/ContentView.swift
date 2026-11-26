import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var app: AppModel
    @State private var showSettings = false
    @State private var pinchStart: CGFloat? = nil
    @State private var focusAt: CGPoint? = nil

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack {
                    CameraPreview(session: app.camera.session)
                    Canvas { ctx, size in drawBoxes(ctx, size) }
                        .allowsHitTesting(false)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(MagnifyGesture()
                            .onChanged { v in
                                if pinchStart == nil { pinchStart = app.camera.zoom }
                                app.camera.setZoom((pinchStart ?? 1) * v.magnification)
                            }
                            .onEnded { _ in pinchStart = nil })
                        .onTapGesture { p in
                            app.camera.focus(at: toImage(p, geo.size))
                            focusAt = p
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { focusAt = nil }
                        }
                    if let f = focusAt {
                        RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 1.5)
                            .frame(width: 64, height: 64).position(f).allowsHitTesting(false)
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let t = app.toast {
                    Text(t).font(.system(size: 14, weight: .medium)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.95)))
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                zoomChips.padding(.bottom, 14)
                bottomBar
            }
            .animation(.easeOut(duration: 0.15), value: app.toast)

            if app.camera.denied {
                VStack(spacing: 12) {
                    Text("카메라 권한이 필요합니다").font(.headline)
                    Text("설정 > 개인정보 보호 > 카메라에서 GgongCam을 켜주세요.").font(.subheadline).foregroundStyle(.secondary)
                    Button("설정 열기") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24).background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.12)))
            }
        }
        .background(Color.black)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings) { SettingsView(app: app) }
        .onAppear { app.start() }
    }

    // MARK: 화면 위
    private var topBar: some View {
        HStack(alignment: .top, spacing: 6) {
            chip {
                Circle().fill(app.models.model == nil ? Color.gray : (app.boxes.isEmpty ? Color(red: 0.56, green: 0.75, blue: 0.62) : .black)).frame(width: 6, height: 6)
                if app.models.model == nil {
                    Text(app.models.status)
                } else {
                    Text("\(app.boxes.count)").fontWeight(.semibold) + Text("개")
                }
            }
            .foregroundStyle(app.boxes.isEmpty ? Color.white.opacity(0.85) : .black)
            .background(Capsule().fill(app.boxes.isEmpty ? Color.black.opacity(0.55) : Color.white.opacity(0.92)))
            if app.shots.pending + app.shots.blocked > 0 {
                chip { Text(app.shots.uploading ? "보내는 중" : "안 보낸 사진 \(app.shots.pending)장") }
                    .foregroundStyle(.white.opacity(0.85)).background(Capsule().fill(.black.opacity(0.55)))
            }
            if app.sleeping {
                chip { Text("절전") }.foregroundStyle(.white.opacity(0.7)).background(Capsule().fill(.black.opacity(0.55)))
            }
            Spacer()
            VStack(spacing: 8) {
                round("slider.horizontal.3", on: false) { showSettings = true }
                if app.camera.hasTorch {
                    round(app.camera.torchOn ? "bolt.fill" : "bolt", on: app.camera.torchOn) { app.camera.setTorch(!app.camera.torchOn) }
                }
                round(app.camera.bright ? "moon.fill" : "moon", on: app.camera.bright) { app.camera.setBright(!app.camera.bright) }
            }
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // MARK: 줌 버튼
    private var zoomChips: some View {
        let opts: [CGFloat] = (app.camera.hasUltraWide ? [0.5] : []) + [1, 2, 3]
        let z = app.camera.zoom
        let best = opts.min { abs($0 - z) < abs($1 - z) } ?? 1
        return HStack(spacing: 8) {
            ForEach(opts, id: \.self) { v in
                let on = v == best
                Button { app.camera.setZoom(v) } label: {
                    Text(on && abs(z - v) > 0.05 ? String(format: "%.1f×", z) : (v == 0.5 ? ".5×" : "\(Int(v))×"))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 40, minHeight: 40)
                        .foregroundStyle(on ? .black : .white.opacity(0.85))
                        .background(Circle().fill(on ? Color.white.opacity(0.95) : Color.black.opacity(0.55)))
                }
            }
        }
    }

    // MARK: 화면 아래 (감지, 촬영, 업로드)
    private var bottomBar: some View {
        HStack {
            Button { app.detecting.toggle() } label: {
                Text(app.detecting ? "감지 켬" : "감지 끔").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(app.detecting ? .white : .white.opacity(0.5))
                    .frame(minWidth: 96, minHeight: 46)
                    .background(Capsule().fill(.black.opacity(0.55)).overlay(Capsule().stroke(.white.opacity(0.22))))
            }
            Spacer()
            Button { app.capture() } label: {
                ZStack {
                    Circle().stroke(.white.opacity(0.92), lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 60, height: 60)
                }
            }
            .accessibilityLabel("사진 저장")
            Spacer()
            Button {
                if app.uploadCode.isEmpty { showSettings = true; app.show("업로드 비밀번호를 먼저 넣으세요") } else { app.uploadNow(quiet: false) }
            } label: {
                (Text("업로드 ") + Text("\(app.shots.pending)").foregroundColor(.white.opacity(0.7)))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(minWidth: 96, minHeight: 46)
                    .background(Capsule().fill(.black.opacity(0.55)).overlay(Capsule().stroke(.white.opacity(0.22))))
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 10)
    }

    private func chip<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 6) { c() }.font(.system(size: 13)).padding(.horizontal, 11).frame(height: 30)
    }

    private func round(_ icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .foregroundStyle(on ? .black : .white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(on ? Color.white.opacity(0.95) : Color.black.opacity(0.55)))
        }
    }

    // MARK: 박스 그리기 (미리보기는 화면을 꽉 채우므로 같은 비율로 맞춘다)
    private func mapping(_ size: CGSize) -> (k: CGFloat, dx: CGFloat, dy: CGFloat) {
        let w = app.imageSize.width, h = app.imageSize.height
        let k = max(size.width / w, size.height / h)
        return (k, (size.width - w * k) / 2, (size.height - h * k) / 2)
    }

    private func toImage(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        let m = mapping(size), w = app.imageSize.width, h = app.imageSize.height
        return CGPoint(x: min(1, max(0, (p.x - m.dx) / (w * m.k))), y: min(1, max(0, (p.y - m.dy) / (h * m.k))))
    }

    private func drawBoxes(_ ctx: GraphicsContext, _ size: CGSize) {
        let m = mapping(size), w = app.imageSize.width, h = app.imageSize.height
        for t in app.boxes {
            let r = CGRect(x: t.rect.minX * w * m.k + m.dx, y: t.rect.minY * h * m.k + m.dy, width: t.rect.width * w * m.k, height: t.rect.height * h * m.k)
            ctx.stroke(Path(r), with: .color(.white.opacity(0.18)), lineWidth: 1)
            let c = max(6, min(16, r.width / 3, r.height / 3))
            var p = Path()
            let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(r.minX, r.minY, 1, 1), (r.maxX, r.minY, -1, 1), (r.minX, r.maxY, 1, -1), (r.maxX, r.maxY, -1, -1)]
            for (px, py, sx, sy) in corners {
                p.move(to: CGPoint(x: px + sx * c, y: py)); p.addLine(to: CGPoint(x: px, y: py)); p.addLine(to: CGPoint(x: px, y: py + sy * c))
            }
            ctx.stroke(p, with: .color(.white), lineWidth: 2.5)
            let label = Text("#\(t.id) 꽁초 \(Int(t.score * 100))%").font(.system(size: 12, weight: .medium)).foregroundColor(.black)
            let resolved = ctx.resolve(label)
            let ts = resolved.measure(in: CGSize(width: 300, height: 30))
            let ty = r.minY > ts.height + 8 ? r.minY - ts.height - 7 : r.minY + 3
            let bg = CGRect(x: r.minX, y: ty, width: ts.width + 12, height: ts.height + 4)
            ctx.fill(Path(roundedRect: bg, cornerRadius: 4), with: .color(.white.opacity(0.95)))
            ctx.draw(resolved, at: CGPoint(x: bg.minX + 6, y: bg.minY + 2), anchor: .topLeading)
        }
    }
}
