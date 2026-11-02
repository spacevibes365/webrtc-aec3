// swift-tools-version:6.0
import PackageDescription

// WebRTC's AEC3 echo canceller, built from source. No unsafeFlags: SwiftPM
// refuses them in remote dependencies, so every setting below is a plain
// define or search path. AVX2 is left off (it needs -mavx2); NEON comes from
// the compiler's own __ARM_NEON through a patch in patches/.
let package = Package(
    name: "WebRTCAEC3",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WebRTCAEC3", targets: ["WebRTCAEC3"]),
    ],
    targets: [
        .target(
            name: "CWebRTCAEC3",
            path: "Sources/CWebRTCAEC3",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("webrtc"),
                .headerSearchPath("abseil"),
                .define("WEBRTC_POSIX"),
                .define("WEBRTC_MAC"),
                .define("WEBRTC_LIBRARY_IMPL"),
                .define("WEBRTC_APM_DEBUG_DUMP", to: "0"),
                .define("NDEBUG"),
                .define("_GNU_SOURCE"),
            ],
            cxxSettings: [
                .headerSearchPath("webrtc"),
                .headerSearchPath("abseil"),
                .define("WEBRTC_POSIX"),
                .define("WEBRTC_MAC"),
                .define("WEBRTC_LIBRARY_IMPL"),
                .define("WEBRTC_APM_DEBUG_DUMP", to: "0"),
                .define("NDEBUG"),
                .define("_GNU_SOURCE"),
            ]
        ),
        .target(
            name: "WebRTCAEC3",
            dependencies: ["CWebRTCAEC3"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WebRTCAEC3Tests",
            dependencies: ["WebRTCAEC3"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
