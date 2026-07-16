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
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "cc39c974bf14624e6ce29fd8722620385fde0762")

let timingEngineDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("TimingEngine/Package.swift").path
)
    ? .package(path: "../TimingEngine")
    : .package(url: "https://github.com/1amageek/TimingEngine.git", revision: "0fecd6f568c7c21ec98ddc3b96aad8eacac44c8c")

let pdkKitDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "29cc9f6f8d24562a7dcb5fd43d8dc6437e695c21")

let signoffToolSupportDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("SignoffToolSupport/Package.swift").path
)
    ? .package(path: "../SignoffToolSupport")
    : .package(url: "https://github.com/1amageek/SignoffToolSupport.git", revision: "7bfd1864edd147c59a1dc79e58f297120d165323")

let toolQualificationDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("ToolQualification/Package.swift").path
)
    ? .package(path: "../ToolQualification")
    : .package(url: "https://github.com/1amageek/ToolQualification.git", revision: "1856a1bc5660febbe2f0358d3e5e0262e496b3d3")

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
