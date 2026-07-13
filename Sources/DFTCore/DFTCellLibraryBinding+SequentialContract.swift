public extension DFTCellLibraryBinding {
    var sequentialCellContract: DFTSequentialCellContract {
        DFTSequentialCellContract(
            cellTypes: [functionalCellType, scanCellType],
            dataPinName: dataPinName,
            outputPinName: outputPinName,
            clockPinNames: clockPinNames,
            scanInPinName: scanInPinName,
            scanEnablePinName: scanEnablePinName,
            resetPinNames: resetPinNames,
            resetPolarity: resetPolarity,
            setPinNames: setPinNames,
            setPolarity: setPolarity,
            controlTiming: controlTiming,
            clockEdge: clockEdge,
            elementKind: elementKind,
            latchEnablePolarity: latchEnablePolarity
        )
    }
}
