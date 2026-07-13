import Foundation

public struct DFTCellLibraryBinding: Sendable, Hashable, Codable {
    public var bindingID: String
    public var functionalCellType: String
    public var scanCellType: String
    public var dataPinName: String
    public var outputPinName: String
    public var clockPinNames: [String]
    public var resetPinNames: [String]
    public var resetPolarity: DFTControlPolarity
    public var setPinNames: [String]
    public var setPolarity: DFTControlPolarity
    public var controlTiming: DFTSequentialControlTiming
    public var clockEdge: DFTClockEdge
    public var elementKind: DFTSequentialElementKind
    public var latchEnablePolarity: DFTControlPolarity
    public var scanInPinName: String
    public var scanEnablePinName: String
    public var testModePinName: String?
    public var timingCellName: String?
    public var legalReplacementGroup: String?
    public var requiredTimingPinNames: [String]

    public init(
        bindingID: String,
        functionalCellType: String,
        scanCellType: String,
        dataPinName: String,
        outputPinName: String,
        clockPinNames: [String],
        resetPinNames: [String] = [],
        resetPolarity: DFTControlPolarity = .activeHigh,
        setPinNames: [String] = [],
        setPolarity: DFTControlPolarity = .activeHigh,
        controlTiming: DFTSequentialControlTiming = .asynchronous,
        clockEdge: DFTClockEdge = .rising,
        elementKind: DFTSequentialElementKind = .edgeTriggered,
        latchEnablePolarity: DFTControlPolarity = .activeHigh,
        scanInPinName: String = "SI",
        scanEnablePinName: String = "SE",
        testModePinName: String? = "TM",
        timingCellName: String? = nil,
        legalReplacementGroup: String? = nil,
        requiredTimingPinNames: [String] = []
    ) {
        self.bindingID = bindingID
        self.functionalCellType = functionalCellType
        self.scanCellType = scanCellType
        self.dataPinName = dataPinName
        self.outputPinName = outputPinName
        self.clockPinNames = clockPinNames
        self.resetPinNames = resetPinNames
        self.resetPolarity = resetPolarity
        self.setPinNames = setPinNames
        self.setPolarity = setPolarity
        self.controlTiming = controlTiming
        self.clockEdge = clockEdge
        self.elementKind = elementKind
        self.latchEnablePolarity = latchEnablePolarity
        self.scanInPinName = scanInPinName
        self.scanEnablePinName = scanEnablePinName
        self.testModePinName = testModePinName
        self.timingCellName = timingCellName
        self.legalReplacementGroup = legalReplacementGroup
        self.requiredTimingPinNames = requiredTimingPinNames
    }

    private enum CodingKeys: String, CodingKey {
        case bindingID
        case functionalCellType
        case scanCellType
        case dataPinName
        case outputPinName
        case clockPinNames
        case resetPinNames
        case resetPolarity
        case setPinNames
        case setPolarity
        case controlTiming
        case clockEdge
        case elementKind
        case latchEnablePolarity
        case scanInPinName
        case scanEnablePinName
        case testModePinName
        case timingCellName
        case legalReplacementGroup
        case requiredTimingPinNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bindingID: try container.decode(String.self, forKey: .bindingID),
            functionalCellType: try container.decode(String.self, forKey: .functionalCellType),
            scanCellType: try container.decode(String.self, forKey: .scanCellType),
            dataPinName: try container.decode(String.self, forKey: .dataPinName),
            outputPinName: try container.decode(String.self, forKey: .outputPinName),
            clockPinNames: try container.decode([String].self, forKey: .clockPinNames),
            resetPinNames: try container.decodeIfPresent([String].self, forKey: .resetPinNames) ?? [],
            resetPolarity: try container.decodeIfPresent(
                DFTControlPolarity.self,
                forKey: .resetPolarity
            ) ?? .activeHigh,
            setPinNames: try container.decodeIfPresent([String].self, forKey: .setPinNames) ?? [],
            setPolarity: try container.decodeIfPresent(
                DFTControlPolarity.self,
                forKey: .setPolarity
            ) ?? .activeHigh,
            controlTiming: try container.decodeIfPresent(
                DFTSequentialControlTiming.self,
                forKey: .controlTiming
            ) ?? .asynchronous,
            clockEdge: try container.decodeIfPresent(DFTClockEdge.self, forKey: .clockEdge) ?? .rising,
            elementKind: try container.decodeIfPresent(
                DFTSequentialElementKind.self,
                forKey: .elementKind
            ) ?? .edgeTriggered,
            latchEnablePolarity: try container.decodeIfPresent(
                DFTControlPolarity.self,
                forKey: .latchEnablePolarity
            ) ?? .activeHigh,
            scanInPinName: try container.decodeIfPresent(String.self, forKey: .scanInPinName) ?? "SI",
            scanEnablePinName: try container.decodeIfPresent(String.self, forKey: .scanEnablePinName) ?? "SE",
            testModePinName: try container.decodeIfPresent(String.self, forKey: .testModePinName) ?? "TM",
            timingCellName: try container.decodeIfPresent(String.self, forKey: .timingCellName),
            legalReplacementGroup: try container.decodeIfPresent(String.self, forKey: .legalReplacementGroup),
            requiredTimingPinNames: try container.decodeIfPresent([String].self, forKey: .requiredTimingPinNames) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bindingID, forKey: .bindingID)
        try container.encode(functionalCellType, forKey: .functionalCellType)
        try container.encode(scanCellType, forKey: .scanCellType)
        try container.encode(dataPinName, forKey: .dataPinName)
        try container.encode(outputPinName, forKey: .outputPinName)
        try container.encode(clockPinNames, forKey: .clockPinNames)
        try container.encode(resetPinNames, forKey: .resetPinNames)
        if resetPolarity != .activeHigh {
            try container.encode(resetPolarity, forKey: .resetPolarity)
        }
        if !setPinNames.isEmpty {
            try container.encode(setPinNames, forKey: .setPinNames)
        }
        if setPolarity != .activeHigh {
            try container.encode(setPolarity, forKey: .setPolarity)
        }
        if controlTiming != .asynchronous {
            try container.encode(controlTiming, forKey: .controlTiming)
        }
        if clockEdge != .rising {
            try container.encode(clockEdge, forKey: .clockEdge)
        }
        if elementKind != .edgeTriggered {
            try container.encode(elementKind, forKey: .elementKind)
        }
        if latchEnablePolarity != .activeHigh {
            try container.encode(latchEnablePolarity, forKey: .latchEnablePolarity)
        }
        try container.encode(scanInPinName, forKey: .scanInPinName)
        try container.encode(scanEnablePinName, forKey: .scanEnablePinName)
        try container.encodeIfPresent(testModePinName, forKey: .testModePinName)
        try container.encodeIfPresent(timingCellName, forKey: .timingCellName)
        try container.encodeIfPresent(legalReplacementGroup, forKey: .legalReplacementGroup)
        if !requiredTimingPinNames.isEmpty {
            try container.encode(requiredTimingPinNames, forKey: .requiredTimingPinNames)
        }
    }
}
