import Foundation
import TimingCore

public struct DFTCellLibraryTimingValidator: DFTCellLibraryTimingValidating {
    public init() {}

    public func validate(
        manifest: DFTCellLibraryManifest,
        timingLibrary: TimingLibrary
    ) throws -> DFTCellLibraryTimingValidationResult {
        let bindingIDs = manifest.bindings.map(\.bindingID)
        var timingCellNames: [String] = []
        var legalReplacementGroups: [String] = []
        var clockToQBindingCount = 0

        for binding in manifest.bindings.sorted(by: { $0.bindingID < $1.bindingID }) {
            guard let group = binding.legalReplacementGroup,
                  !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DFTCellLibraryTimingError.bindingGroupMissing(binding.bindingID)
            }
            let timingCellName = binding.timingCellName ?? binding.scanCellType
            guard let timingCell = timingLibrary.cells[timingCellName] else {
                throw DFTCellLibraryTimingError.timingCellMissing(
                    bindingID: binding.bindingID,
                    cellName: timingCellName
                )
            }
            var requiredPinNames: [String] = []
            requiredPinNames.append(binding.dataPinName)
            requiredPinNames.append(binding.outputPinName)
            requiredPinNames.append(binding.scanInPinName)
            requiredPinNames.append(binding.scanEnablePinName)
            requiredPinNames.append(contentsOf: binding.clockPinNames)
            requiredPinNames.append(contentsOf: binding.resetPinNames)
            requiredPinNames.append(contentsOf: binding.setPinNames)
            requiredPinNames.append(contentsOf: binding.requiredTimingPinNames)
            if let testModePinName = binding.testModePinName {
                requiredPinNames.append(testModePinName)
            }
            let requiredPins = Set(requiredPinNames)
            let availablePins = Set(timingCell.pins.map(\.name))
            guard let missingPin = requiredPins
                .sorted()
                .first(where: { !availablePins.contains($0) }) else {
                let model = timingCell.sequentialModel
                guard let model else {
                    throw DFTCellLibraryTimingError.sequentialModelMissing(
                        bindingID: binding.bindingID,
                        cellName: timingCellName
                    )
                }
                guard model.dataPin == binding.dataPinName else {
                    throw DFTCellLibraryTimingError.sequentialPinMismatch(
                        bindingID: binding.bindingID,
                        expected: binding.dataPinName,
                        actual: model.dataPin
                    )
                }
                guard model.outputPin == binding.outputPinName else {
                    throw DFTCellLibraryTimingError.sequentialPinMismatch(
                        bindingID: binding.bindingID,
                        expected: binding.outputPinName,
                        actual: model.outputPin
                    )
                }
                guard model.clockPin == binding.clockPinNames[0] else {
                    throw DFTCellLibraryTimingError.sequentialPinMismatch(
                        bindingID: binding.bindingID,
                        expected: binding.clockPinNames[0],
                        actual: model.clockPin
                    )
                }
                guard model.clockToQ != nil else {
                    throw DFTCellLibraryTimingError.clockToQArcMissing(
                        bindingID: binding.bindingID,
                        cellName: timingCellName
                    )
                }
                clockToQBindingCount += 1
                timingCellNames.append(timingCellName)
                legalReplacementGroups.append(group)
                continue
            }
            throw DFTCellLibraryTimingError.requiredPinMissing(
                bindingID: binding.bindingID,
                pinName: missingPin
            )
        }

        return DFTCellLibraryTimingValidationResult(
            processID: manifest.processID,
            pdkDigest: manifest.pdkDigest,
            validatedBindingIDs: bindingIDs.sorted(),
            timingCellNames: Array(Set(timingCellNames)).sorted(),
            legalReplacementGroups: Array(Set(legalReplacementGroups)).sorted(),
            clockToQBindingCount: clockToQBindingCount
        )
    }
}
