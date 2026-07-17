// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)

let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac")

let logicDesignDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "09768ed203d97d1d0f79f786f9988fcb2cd39155")

let timingEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("TimingEngine/Package.swift").path
)
    ? .package(path: "../TimingEngine")
    : .package(url: "https://github.com/1amageek/TimingEngine.git", revision: "81898ed51ab05c62712ebca5b1b03869b89f7682")

let pdkKitDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "28f3b83304ad2bbb0c2e0269d26616081d90d992")

let signoffToolSupportDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("SignoffToolSupport/Package.swift").path
)
    ? .package(path: "../SignoffToolSupport")
    : .package(url: "https://github.com/1amageek/SignoffToolSupport.git", revision: "2c8ce00a8f873934e74e3f219e0cbd122a862fe9")

let package = Package(
    name: "DFTEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DFTCore", targets: ["DFTCore"]),
        .library(name: "ScanInsertion", targets: ["ScanInsertion"]),
        .library(name: "ATPGEngine", targets: ["ATPGEngine"]),
        .library(name: "BISTEngine", targets: ["BISTEngine"]),
        .library(name: "DFTEngine", targets: ["DFTEngine"]),
        .executable(name: "dft-engine", targets: ["DFTCLI"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
        logicDesignDependency,
        timingEngineDependency,
        pdkKitDependency,
        signoffToolSupportDependency,
    ],
    targets: [
        .target(
            name: "DFTCore",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "TimingCore", package: "TimingEngine"),
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport")
            ]
        ),
        .target(
            name: "ScanInsertion",
            dependencies: [
                .product(name: "PDKCore", package: "PDKKit"),
                "DFTCore"
            ]
        ),
        .target(
            name: "ATPGEngine",
            dependencies: [
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "PDKCore", package: "PDKKit"),
                "DFTCore",
            ]
        ),
        .target(
            name: "BISTEngine",
            dependencies: [
                "DFTCore",
            ]
        ),
        .target(
            name: "DFTEngine",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                "DFTCore",
                "ScanInsertion",
                "ATPGEngine",
                "BISTEngine",
            ]
        ),
        .executableTarget(
            name: "DFTCLI",
            dependencies: ["DFTCore", "ScanInsertion", "ATPGEngine", "BISTEngine", "DFTEngine"]
        ),
        .testTarget(
            name: "DFTEngineTests",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                "DFTCore",
                "ScanInsertion",
                "ATPGEngine",
                "BISTEngine",
                "DFTEngine",
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
