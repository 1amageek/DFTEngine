import DFTCore
import Testing
import TimingCore

@Suite("DFT cell-library timing contract")
struct DFTCellLibraryTimingValidatorTests {
    @Test("validator accepts a legal sequential scan replacement")
    func acceptsLegalReplacement() throws {
        let manifest = DFTCellLibraryManifest(
            processID: "fixture-process",
            version: "1",
            pdkDigest: String(repeating: "a", count: 64),
            bindings: [binding()],
            qualification: DFTQualificationProvenance(status: .corpusChecked)
        )
        let library = TimingLibrary(
            name: "fixture-liberty",
            cells: ["SDFF": timingCell()]
        )

        let result = try DFTCellLibraryTimingValidator().validate(
            manifest: manifest,
            timingLibrary: library
        )

        #expect(result.validatedBindingIDs == ["dff-to-sdff"])
        #expect(result.timingCellNames == ["SDFF"])
        #expect(result.legalReplacementGroups == ["scan-flops"])
        #expect(result.clockToQBindingCount == 1)
    }

    @Test("validator blocks a scan mapping without clock-to-Q timing")
    func blocksMissingClockToQ() throws {
        let manifest = DFTCellLibraryManifest(
            processID: "fixture-process",
            version: "1",
            pdkDigest: String(repeating: "a", count: 64),
            bindings: [binding()],
            qualification: DFTQualificationProvenance(status: .corpusChecked)
        )
        var cell = timingCell()
        cell.sequentialModel?.clockToQ = nil
        let library = TimingLibrary(name: "fixture-liberty", cells: ["SDFF": cell])

        do {
            _ = try DFTCellLibraryTimingValidator().validate(
                manifest: manifest,
                timingLibrary: library
            )
            Issue.record("A scan replacement without clock-to-Q timing must be blocked")
        } catch let error as DFTCellLibraryTimingError {
            #expect(error == .clockToQArcMissing(bindingID: "dff-to-sdff", cellName: "SDFF"))
        }
    }

    private func binding() -> DFTCellLibraryBinding {
        DFTCellLibraryBinding(
            bindingID: "dff-to-sdff",
            functionalCellType: "DFF",
            scanCellType: "SDFF",
            dataPinName: "D",
            outputPinName: "Q",
            clockPinNames: ["CLK"],
            scanInPinName: "SI",
            scanEnablePinName: "SE",
            testModePinName: "TM",
            legalReplacementGroup: "scan-flops"
        )
    }

    private func timingCell() -> TimingCell {
        let arc = TimingArc(
            fromPin: "CLK",
            toPin: "Q",
            sense: .positiveUnate,
            delayRise: .constant(0.1),
            delayFall: .constant(0.1),
            transitionRise: .constant(0.1),
            transitionFall: .constant(0.1)
        )
        return TimingCell(
            name: "SDFF",
            pins: [
                TimingPin(name: "D", direction: .input, isData: true),
                TimingPin(name: "CLK", direction: .input, isClock: true),
                TimingPin(name: "SI", direction: .input),
                TimingPin(name: "SE", direction: .input),
                TimingPin(name: "TM", direction: .input),
                TimingPin(name: "Q", direction: .output),
            ],
            arcs: [arc],
            sequentialModel: TimingSequentialModel(
                dataPin: "D",
                clockPin: "CLK",
                outputPin: "Q",
                clockToQ: arc
            )
        )
    }
}
