import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    private let tagList: [(String, String)] = [("paver", "보도블록"), ("asphalt", "아스팔트"), ("soil", "화단·흙"), ("grass", "잔디"),
                                              ("indoor", "실내"), ("night", "밤"), ("wet", "비 온 뒤"), ("far", "멀리서")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("감도", selection: $app.sensitivity) {
                        Text("낮음").tag(65); Text("보통").tag(50); Text("높음").tag(35)
                    }
                    .pickerStyle(.segmented)
                    Toggle("자동 정밀 (멀리 있는 작은 꽁초)", isOn: $app.precise)
                } header: { Text("감지") } footer: {
                    Text("자동 정밀은 전체 화면과 함께 화면 조각을 하나씩 돌아가며 크게 봅니다. 꽁초가 너무 많이 잡히면 감도를 낮추세요.")
                }

                Section {
                    Toggle("꽁초를 확실히 잡으면 자동 저장", isOn: $app.lockCapture)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("장면 태그").font(.subheadline).foregroundStyle(.secondary)
                        FlowTags(items: tagList, selected: $app.tags)
                    }
                    .padding(.vertical, 4)
                } header: { Text("사진 모으기") } footer: {
                    Text("찍은 사진은 학습용으로 올라갑니다. 학습에 안 쓰는 시험용 사진은 박스를 확인해야 해서 웹(ggongcam.pages.dev)에서 찍어 주세요. 사람 얼굴이 보이는 사진은 자동으로 업로드에서 빠집니다.")
                }

                Section {
                    TextField("업로드 비밀번호", text: $app.uploadCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("저장하면 바로 보내기", isOn: $app.autoUpload)
                    LabeledContent("안 보낸 사진", value: "\(app.shots.pending)장")
                    LabeledContent("보낸 사진", value: "\(app.shots.sentTotal)장")
                    if app.shots.blocked > 0 {
                        Button("얼굴이 보이는 사진 \(app.shots.blocked)장 지우기", role: .destructive) { app.shots.deleteBlocked() }
                    }
                    Button(app.shots.uploading ? "보내는 중" : "지금 보내기") { app.uploadNow(quiet: false) }
                        .disabled(app.shots.uploading)
                    if !app.shots.note.isEmpty { Text(app.shots.note).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("학습 데이터로 보내기") } footer: {
                    Text("웹과 같은 서버와 비밀번호를 씁니다. 인터넷이 안 될 때 찍은 사진은 앱에 남아 있다가 다음에 보냅니다.")
                }

                Section {
                    LabeledContent("상태", value: app.models.status)
                    LabeledContent("버전", value: app.models.version.isEmpty ? "-" : app.models.version)
                    LabeledContent("권장 기준", value: "\(Int(app.models.recConf * 100))%")
                    LabeledContent("속도", value: String(format: "%.0f fps", app.fps))
                    Button(app.models.busy ? "확인 중" : "새 모델 확인") { Task { await app.models.checkUpdate(force: false) } }
                        .disabled(app.models.busy)
                } header: { Text("감지 모델") } footer: {
                    Text("앱이 켜질 때마다 사이트에서 새 모델이 있는지 확인하고 자동으로 받습니다. 재학습해도 앱을 다시 설치할 필요가 없습니다.")
                }

                Section {
                    Link("웹으로 열기 (검수, 로봇 연결)", destination: Site.base)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 태그 버튼을 여러 줄로 늘어놓는다.
struct FlowTags: View {
    let items: [(String, String)]
    @Binding var selected: Set<String>

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 84), spacing: 6)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { item in
                let id = item.0, name = item.1
                let on = selected.contains(id)
                Button {
                    if on { selected.remove(id) } else { selected.insert(id) }
                } label: {
                    Text(name).font(.system(size: 13)).frame(maxWidth: .infinity, minHeight: 30)
                        .foregroundStyle(on ? Color.black : Color.primary)
                        .background(Capsule().fill(on ? Color.white : Color.gray.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
