// swift-tools-version:5.10
import PackageDescription

// Three layers, split so an iOS client can reuse the terminal without the
// AppKit shell. KuddoCore and KuddoRender build for both platforms; KuddoApp
// and the executable are macOS-only and simply aren't depended on from iOS.
//
// Cross-target symbols use `package` rather than `public`: it restores exactly
// the visibility these files had as one module, without exporting the parser's
// internals to anything outside this package.
let package = Package(
    name: "Kuddo",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "KuddoCore", targets: ["KuddoCore"]),
        .library(name: "KuddoRender", targets: ["KuddoRender"]),
        .library(name: "KuddoApp", targets: ["KuddoApp"]),
        .executable(name: "Kuddo", targets: ["Kuddo"])
    ],
    targets: [
        .target(
            name: "CKuddoBridge",
            path: "Sources/CKuddoBridge",
            publicHeadersPath: "include"
        ),
        // Parser, grid, themes, triggers, tmux control mapping, key encoding.
        // Foundation/CoreText only — no AppKit, no PTY, no window.
        .target(
            name: "KuddoCore",
            path: "Sources/KuddoCore"
        ),
        // Glyph atlas and the Metal cell pipeline. CAMetalLayer exists on both
        // platforms; the NSView that hosts it does not, so it stays in KuddoApp.
        .target(
            name: "KuddoRender",
            dependencies: ["KuddoCore"],
            path: "Sources/KuddoRender"
        ),
        .target(
            name: "KuddoApp",
            dependencies: ["KuddoCore", "KuddoRender", "CKuddoBridge"],
            path: "Sources/KuddoApp"
        ),
        .executableTarget(
            name: "Kuddo",
            dependencies: ["KuddoApp"],
            path: "Sources/Kuddo"
        )
    ]
)
