import Foundation

public struct DFTSequentialCellContract: Sendable, Hashable, Codable {
    public var cellTypes: [String]
    public var dataPinName: String
    public var outputPinName: String
    public var clockPinNames: [String]
    public var scanInPinName: String?
    public var scanEnablePinName: String?
    public var resetPinNames: [String]
    public var resetPolarity: DFTControlPolarity
    public var setPinNames: [String]
    public var setPolarity: DFTControlPolarity
    public var controlTiming: DFTSequentialControlTiming
    public var clockEdge: DFTClockEdge
    public var elementKind: DFTSequentialElementKind
    public var latchEnablePolarity: DFTControlPolarity

    public init(
        cellTypes: [String],
        dataPinName: String = "D",
        outputPinName: String = "Q",
        clockPinNames: [String] = ["CLK"],
        scanInPinName: String? = nil,
        scanEnablePinName: String? = nil,
        resetPinNames: [String] = [],
        resetPolarity: DFTControlPolarity = .activeHigh,
        setPinNames: [String] = [],
        setPolarity: DFTControlPolarity = .activeHigh,
        controlTiming: DFTSequentialControlTiming = .asynchronous,
        clockEdge: DFTClockEdge = .rising,
        elementKind: DFTSequentialElementKind = .edgeTriggered,
        latchEnablePolarity: DFTControlPolarity = .activeHigh
    ) {
        self.cellTypes = cellTypes.sorted()
        self.dataPinName = dataPinName
        self.outputPinName = outputPinName
        self.clockPinNames = clockPinNames
        self.scanInPinName = scanInPinName
        self.scanEnablePinName = scanEnablePinName
        self.resetPinNames = resetPinNames
        self.resetPolarity = resetPolarity
        self.setPinNames = setPinNames
        self.setPolarity = setPolarity
        self.controlTiming = controlTiming
        self.clockEdge = clockEdge
        self.elementKind = elementKind
        self.latchEnablePolarity = latchEnablePolarity
    }

    private enum CodingKeys: String, CodingKey {
        case cellTypes
        case dataPinName
        case outputPinName
        case clockPinNames
        case scanInPinName
        case scanEnablePinName
        case resetPinNames
        case resetPolarity
        case setPinNames
        case setPolarity
        case controlTiming
        case clockEdge
        case elementKind
        case latchEnablePolarity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cellTypes: try container.decode([String].self, forKey: .cellTypes),
            dataPinName: try container.decode(String.self, forKey: .dataPinName),
            outputPinName: try container.decode(String.self, forKey: .outputPinName),
            clockPinNames: try container.decode([String].self, forKey: .clockPinNames),
            scanInPinName: try container.decodeIfPresent(String.self, forKey: .scanInPinName),
            scanEnablePinName: try container.decodeIfPresent(String.self, forKey: .scanEnablePinName),
            resetPinNames: try container.decode([String].self, forKey: .resetPinNames),
            resetPolarity: try container.decode(
                DFTControlPolarity.self,
                forKey: .resetPolarity
            ),
            setPinNames: try container.decode([String].self, forKey: .setPinNames),
            setPolarity: try container.decode(
                DFTControlPolarity.self,
                forKey: .setPolarity
            ),
            controlTiming: try container.decode(
                DFTSequentialControlTiming.self,
                forKey: .controlTiming
            ),
            clockEdge: try container.decode(DFTClockEdge.self, forKey: .clockEdge),
            elementKind: try container.decode(
                DFTSequentialElementKind.self,
                forKey: .elementKind
            ),
            latchEnablePolarity: try container.decode(
                DFTControlPolarity.self,
                forKey: .latchEnablePolarity
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cellTypes, forKey: .cellTypes)
        try container.encode(dataPinName, forKey: .dataPinName)
        try container.encode(outputPinName, forKey: .outputPinName)
        try container.encode(clockPinNames, forKey: .clockPinNames)
        try container.encodeIfPresent(scanInPinName, forKey: .scanInPinName)
        try container.encodeIfPresent(scanEnablePinName, forKey: .scanEnablePinName)
        try container.encode(resetPinNames, forKey: .resetPinNames)
        try container.encode(resetPolarity, forKey: .resetPolarity)
        try container.encode(setPinNames, forKey: .setPinNames)
        try container.encode(setPolarity, forKey: .setPolarity)
        try container.encode(controlTiming, forKey: .controlTiming)
        try container.encode(clockEdge, forKey: .clockEdge)
        try container.encode(elementKind, forKey: .elementKind)
        try container.encode(latchEnablePolarity, forKey: .latchEnablePolarity)
    }

    public func matches(cellType: String) -> Bool {
        let normalizedCellType = Self.normalize(cellType)
        return cellTypes.contains { declaredType in
            let normalizedDeclaredType = Self.normalize(declaredType)
            return normalizedCellType == normalizedDeclaredType
                || normalizedCellType.hasPrefix(normalizedDeclaredType)
        }
    }

    private static func normalize(_ value: String) -> String {
        value.uppercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
