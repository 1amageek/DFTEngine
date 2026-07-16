// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let circuiteFoundationDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac")

let logicDesignDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "8e0c8c2c63152aa45bf12d943fa034bb1aba0f1e")

let timingEngineDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("TimingEngine/Package.swift").path
)
    ? .package(path: "../TimingEngine")
    : .package(url: "https://github.com/1amageek/TimingEngine.git", revision: "5b2f711d355af8a204819c6ed33f98ef722e379c")

let pdkKitDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "aa145dfaa67454c44ac7767c37a28ab7f4b1d2e2")

let signoffToolSupportDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("SignoffToolSupport/Package.swift").path
)
    ? .package(path: "../SignoffToolSupport")
    : .package(url: "https://github.com/1amageek/SignoffToolSupport.git", revision: "597c44065b6b717e903623adb8aabcf2ac367697")

let toolQualificationDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("ToolQualification/Package.swift").path
)
    ? .package(path: "../ToolQualification")
    : .package(url: "https://github.com/1amageek/ToolQualification.git", revision: "32b031b5322f1ccb0ef78466faab0f895d47c4fd")

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
        toolQualificationDependency,
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
                .product(name: "ToolQualification", package: "ToolQualification"),
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
                .product(name: "ToolQualification", package: "ToolQualification"),
                "DFTEngine",
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
