# 꽁캠 아이폰 앱

웹(ggongcam.pages.dev)과 같은 서버, 같은 업로드 비밀번호, 같은 학습 흐름을 쓰는 아이폰 앱이다.
웹은 그대로 두고, 앱은 현장에서 찍고 감지하는 기능만 가진다. 검수, 시험용 촬영, 로봇 연결은 웹에서 한다.

## 웹과 같은 점
- 감지 모델: 앱이 켜질 때 `models/ios.json`을 보고 새 버전이면 받아서 바꾼다. 재학습하면 학습 워크플로가 아이폰용 모델(CoreML)도 같이 만들어 올리므로 앱을 다시 설치할 필요가 없다. 지금 가중치로 바로 다시 만들려면 Actions에서 `export-ios`를 실행한다.
- 업로드: `/api/upload`로 보낸다. 사진은 `data/extra/phone/날짜/`에 들어가 새벽 학습에 쓰인다. 파일 이름 끝이 `_ios`다.
- 감도: 낮음/보통/높음이 모델 권장 기준(`ios.json`의 `conf`)에 맞춰진다.

## 앱에서만 되는 것
- 플래시, 실제 0.5x 초광각과 광학 줌(가상 카메라), 탭 초점, 야간 노출 보정
- Apple Neural Engine으로 감지해서 빠르고 덜 뜨겁다

## 처음 설치 (맥)
1. 이 저장소를 받는다: `git clone https://github.com/kjm030131-cell/ggongcam.git`
2. Finder에서 `ggongcam/ios/GgongCam.swiftpm`을 더블클릭하면 Xcode로 열린다.
3. 아이폰을 USB로 연결하고, 아이폰에서 **설정 > 개인정보 보호 및 보안 > 개발자 모드**를 켠다(재부팅됨).
4. Xcode 왼쪽에서 GgongCam을 누르고 **Signing & Capabilities > Team**에서 내 Apple ID를 고른다. 없으면 Add Account로 로그인.
5. Xcode 위쪽 기기 목록에서 내 아이폰을 고르고 실행(▶) 버튼.
6. 처음 실행하면 아이폰에서 **설정 > 일반 > VPN 및 기기 관리**에서 내 Apple ID 개발자를 신뢰해야 열린다.

무료 Apple ID로 설치한 앱은 7일 뒤 실행이 안 된다. 그때 4~5번을 다시 하면 된다.

## 앱 코드 구조
| 파일 | 하는 일 |
|---|---|
| `Camera.swift` | 뒤 카메라, 줌(0.5x부터), 플래시, 초점, 노출 |
| `Detector.swift` | 모델 받기/바꾸기, Vision 감지(전체 + 조각 하나씩), 추적과 락온 |
| `Store.swift` | 사진 저장, 얼굴 확인, 업로드와 대기열 |
| `AppModel.swift` | 위 셋을 잇는다. 감지는 카메라 큐에서 돈다 |
| `ContentView.swift`, `SettingsView.swift` | 화면 |
