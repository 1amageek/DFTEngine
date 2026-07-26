import DFTPatternExchange
import Foundation
import Testing

@Suite("DFT pattern exchange")
struct DFTPatternExchangeTests {
    @Test("rich exchange program validates exact timing and cycle coverage")
    func validatesProgram() throws {
        try DFTPatternExchangeValidator().validate(makeProgram())
    }

    @Test("canonical STIL preserves the complete rich exchange program")
    func roundTripsCanonicalSTIL() throws {
        let program = makeProgram()
        let codec = STILPatternCodec()

        let data = try codec.encode(program)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("STIL 1.0;"))
        #expect(text.contains("WaveformTable \"shift\""))
        #expect(text.contains("Call \"pattern_0_shift\";"))
        #expect(try codec.decode(data) == program)
    }

    @Test("STIL capability declares every accepted semantic")
    func declaresCapability() {
        let capability = STILPatternCodec().capability

        #expect(capability.profileID == "lsi-stil-1.0-cycle-v1")
        #expect(capability.standardVersion == "STIL 1.0")
        #expect(capability.textEncoding == "US-ASCII")
        #expect(capability.timeUnit == "ps")
        #expect(capability.supportedActions == [
            .driveLow,
            .driveHigh,
            .driveHighImpedance,
            .compareLow,
            .compareHigh,
            .mask,
        ])
        #expect(capability.supportsSignalGroups)
        #expect(capability.supportsProcedures)
        #expect(capability.supportsPatternBursts)
        #expect(!capability.supportsEscapedIdentifiers)
    }

    @Test("checked-in STIL fixture decodes without producer state")
    func decodesIndependentFixture() throws {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "pattern-exchange",
                withExtension: "stil",
                subdirectory: "Fixtures"
            )
        )
        let fixture = try Data(contentsOf: fixtureURL)
        let codec = STILPatternCodec()
        let decoded = try codec.decode(fixture)

        #expect(decoded == makeProgram())
        #expect(try codec.encode(decoded) == fixture)
    }

    @Test(
        "streaming STIL codec stays within the large-pattern latency budget",
        .timeLimit(.minutes(1))
    )
    func largePatternPerformanceBudget() throws {
        let cycleCount = 20_000
        var program = makeProgram()
        let cycle = try #require(program.procedures.first?.cycles.first)
        program.procedures[0].cycles = Array(repeating: cycle, count: cycleCount)
        let codec = STILPatternCodec()
        let clock = ContinuousClock()
        let startedAt = clock.now

        let encoded = try codec.encode(program)
        let decoded = try codec.decode(encoded)

        let elapsed = startedAt.duration(to: clock.now)
        #expect(decoded.procedures[0].cycles.count == cycleCount)
        #expect(encoded.count > 1_000_000)
        #expect(elapsed < .seconds(5))
    }

    @Test("unsupported STIL sections fail instead of being ignored")
    func rejectsUnsupportedSTILSection() throws {
        let codec = STILPatternCodec()
        let encoded = try codec.encode(makeProgram())
        let text = try #require(String(data: encoded, encoding: .utf8))
        let unsupported = text.replacingOccurrences(
            of: "Procedures {",
            with: "MacroDefs {"
        )

        #expect(throws: DFTPatternExchangeError.self) {
            _ = try codec.decode(Data(unsupported.utf8))
        }
    }

    @Test("non-picosecond STIL timing fails explicitly")
    func rejectsUnsupportedTimeUnit() throws {
        let codec = STILPatternCodec()
        let encoded = try codec.encode(makeProgram())
        let text = try #require(String(data: encoded, encoding: .utf8))
        let unsupported = text.replacingOccurrences(
            of: "10000ps",
            with: "10ns"
        )

        #expect(throws: DFTPatternExchangeError.self) {
            _ = try codec.decode(Data(unsupported.utf8))
        }
    }

    @Test("invalid STIL text encoding fails explicitly")
    func rejectsInvalidTextEncoding() {
        #expect(throws: DFTPatternExchangeError.self) {
            _ = try STILPatternCodec().decode(Data([0xFF, 0xFE]))
        }
    }

    @Test("cycle must assign every signal exactly once")
    func rejectsIncompleteCycle() {
        var program = makeProgram()
        program.procedures[0].cycles[0].assignments.removeLast()

        #expect(throws: DFTPatternExchangeError.self) {
            try DFTPatternExchangeValidator().validate(program)
        }
    }

    @Test("output-only signals reject drive waveforms")
    func rejectsOutputDriveAction() {
        var program = makeProgram()
        let outputIndex = program.timingSets[0].waveforms.firstIndex {
            $0.signalName == "scan_out"
        }
        guard let outputIndex else {
            Issue.record("Missing scan_out waveform")
            return
        }
        program.timingSets[0].waveforms[outputIndex].symbols[0].events[0].action = .driveLow

        #expect(throws: DFTPatternExchangeError.self) {
            try DFTPatternExchangeValidator().validate(program)
        }
    }

    @Test("overlapping group and scalar assignments are rejected")
    func rejectsOverlappingAssignments() {
        var program = makeProgram()
        program.procedures[0].cycles[0].assignments.insert(
            DFTPatternAssignment(target: "scan_in", symbols: "0"),
            at: 1
        )

        #expect(throws: DFTPatternExchangeError.self) {
            try DFTPatternExchangeValidator().validate(program)
        }
    }

    private func makeProgram() -> DFTPatternExchangeProgram {
        DFTPatternExchangeProgram(
            name: "sky130_scan",
            signals: [
                DFTPatternSignal(name: "scan_clk", direction: .input),
                DFTPatternSignal(name: "scan_in", direction: .input),
                DFTPatternSignal(name: "scan_out", direction: .output),
            ],
            signalGroups: [
                DFTPatternSignalGroup(
                    name: "drive",
                    signalNames: ["scan_clk", "scan_in"]
                ),
            ],
            timingSets: [
                DFTPatternTimingSet(
                    name: "shift",
                    periodPicoseconds: 10_000,
                    waveforms: [
                        inputWaveform(name: "scan_clk"),
                        inputWaveform(name: "scan_in"),
                        DFTSignalWaveform(
                            signalName: "scan_out",
                            symbols: [
                                DFTWaveformSymbol(
                                    symbol: "L",
                                    events: [
                                        DFTWaveformEvent(
                                            offsetPicoseconds: 9_000,
                                            action: .compareLow
                                        ),
                                    ]
                                ),
                                DFTWaveformSymbol(
                                    symbol: "H",
                                    events: [
                                        DFTWaveformEvent(
                                            offsetPicoseconds: 9_000,
                                            action: .compareHigh
                                        ),
                                    ]
                                ),
                                DFTWaveformSymbol(
                                    symbol: "X",
                                    events: [
                                        DFTWaveformEvent(
                                            offsetPicoseconds: 9_000,
                                            action: .mask
                                        ),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            procedures: [
                DFTPatternProcedure(
                    name: "pattern_0_shift",
                    cycles: [
                        DFTPatternCycle(
                            timingSetName: "shift",
                            assignments: [
                                DFTPatternAssignment(target: "drive", symbols: "10"),
                                DFTPatternAssignment(target: "scan_out", symbols: "L"),
                            ]
                        ),
                    ]
                ),
            ],
            patterns: [
                DFTPatternCase(
                    id: "pattern_0",
                    procedureNames: ["pattern_0_shift"]
                ),
            ]
        )
    }

    private func inputWaveform(name: String) -> DFTSignalWaveform {
        DFTSignalWaveform(
            signalName: name,
            symbols: [
                DFTWaveformSymbol(
                    symbol: "0",
                    events: [
                        DFTWaveformEvent(offsetPicoseconds: 0, action: .driveLow),
                    ]
                ),
                DFTWaveformSymbol(
                    symbol: "1",
                    events: [
                        DFTWaveformEvent(offsetPicoseconds: 0, action: .driveHigh),
                    ]
                ),
                DFTWaveformSymbol(
                    symbol: "Z",
                    events: [
                        DFTWaveformEvent(
                            offsetPicoseconds: 0,
                            action: .driveHighImpedance
                        ),
                    ]
                ),
            ]
        )
    }
}
