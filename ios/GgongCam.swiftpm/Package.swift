// swift-tools-version: 5.9

// 꽁캠 아이폰 앱. Xcode에서 이 폴더(GgongCam.swiftpm)를 열고, 위쪽에서 내 아이폰을 고른 뒤 실행하면 된다.
// 처음 한 번은 Signing & Capabilities 에서 Team(내 Apple ID)을 골라야 한다. 고르면 아래 teamIdentifier 가 자동으로 채워진다.
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "GgongCam",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "GgongCam",
            targets: ["AppModule"],
            bundleIdentifier: "dev.ggongcam.app",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .camera),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait
            ],
            capabilities: [
                .camera(purposeString: "바닥의 담배꽁초를 찾고 학습용 사진을 찍으려면 카메라가 필요합니다."),
                .outgoingNetworkConnections()
            ],
            appCategory: .utilities
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
