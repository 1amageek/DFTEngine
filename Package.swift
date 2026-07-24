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
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "7abcac83517935c9b9f7553d7016d62cffde259d")

let logicDesignDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "4894cd89862f43300a3ca9d4cf73b3d9e6034626")

let timingEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("TimingEngine/Package.swift").path
)
    ? .package(path: "../TimingEngine")
    : .package(url: "https://github.com/1amageek/TimingEngine.git", revision: "709af87cf5c898d47605b0ab287786828ee2267c")

let pdkKitDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "b62c5ad7e5819a24977038c2133856caed52f481")

let signoffToolSupportDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("SignoffToolSupport/Package.swift").path
)
    ? .package(path: "../SignoffToolSupport")
    : .package(url: "https://github.com/1amageek/SignoffToolSupport.git", revision: "6bf675eecb27e3bd3440c5ce8a85c85c510fc3cb")

let package = Package(
    name: "DFTEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DFTCore", targets: ["DFTCore"]),
        .library(name: "ScanInsertion", targets: ["ScanInsertion"]),
        .library(name: "ATPGEngine", targets: ["ATPGEngine"]),
        .library(name: "BISTEngine", targets: ["BISTEngine"]),
        .library(name: "DFTExternalTools", targets: ["DFTExternalTools"]),
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
                .product(name: "PDKCore", package: "PDKKit")
            ]
        ),
        .target(
            name: "DFTExternalTools",
            dependencies: [
                "DFTCore",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport"),
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
                "DFTExternalTools",
                "DFTEngine",
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
