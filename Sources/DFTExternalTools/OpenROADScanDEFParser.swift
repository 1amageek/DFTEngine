import Foundation

struct OpenROADScanDEFParser: Sendable {
    func parse(_ data: Data) throws -> [OpenROADScanDEFChain] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw OpenROADDFTScanImportError.inputTextInvalid(name: "ScanDEF")
        }
        var state = State(tokens: tokenize(text))
        try state.seek(to: "SCANCHAINS")
        let declaredCount = try state.readInteger()
        try state.expect(";")
        var chains: [OpenROADScanDEFChain] = []
        while state.current != "END" {
            chains.append(try state.parseChain())
        }
        try state.expect("END")
        try state.expect("SCANCHAINS")
        guard chains.count == declaredCount else {
            throw OpenROADDFTScanImportError.scanDEFInvalid(
                "declared \(declaredCount) chains but decoded \(chains.count)"
            )
        }
        return chains
    }

    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inComment = false
        for character in text {
            if inComment {
                if character == "\n" {
                    inComment = false
                }
                continue
            }
            if character == "#" {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                inComment = true
            } else if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else if "();+-".contains(character) {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                tokens.append(String(character))
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        tokens.append("")
        return tokens
    }

    private struct State {
        var tokens: [String]
        var index = 0

        var current: String {
            tokens[min(index, tokens.count - 1)]
        }

        mutating func advance() -> String {
            let value = current
            if !value.isEmpty {
                index += 1
            }
            return value
        }

        mutating func seek(to token: String) throws {
            while !current.isEmpty, current != token {
                _ = advance()
            }
            try expect(token)
        }

        mutating func expect(_ token: String) throws {
            guard advance() == token else {
                throw OpenROADDFTScanImportError.scanDEFInvalid(
                    "expected '\(token)' near token \(index)"
                )
            }
        }

        mutating func readValue(_ label: String) throws -> String {
            let value = advance()
            guard !value.isEmpty, !["+", "-", "(", ")", ";"].contains(value) else {
                throw OpenROADDFTScanImportError.scanDEFInvalid(
                    "\(label) is missing near token \(index)"
                )
            }
            return value
        }

        mutating func readInteger() throws -> Int {
            let value = try readValue("integer")
            guard let integer = Int(value), integer >= 0 else {
                throw OpenROADDFTScanImportError.scanDEFInvalid(
                    "\(value) is not a non-negative integer"
                )
            }
            return integer
        }

        mutating func parseChain() throws -> OpenROADScanDEFChain {
            try expect("-")
            let chainID = try readValue("chain ID")
            var startSignal: String?
            var stopSignal: String?
            var domainID: String?
            var elements: [OpenROADScanDEFElement] = []
            var commonInputPin: String?
            var commonOutputPin: String?
            while current != "-", current != "END", !current.isEmpty {
                try expect("+")
                let section = advance()
                switch section {
                case "START":
                    startSignal = try parseTopLevelEndpoint("START")
                case "STOP":
                    stopSignal = try parseTopLevelEndpoint("STOP")
                    try expect(";")
                case "PARTITION":
                    domainID = try readValue("partition")
                case "COMMONSCANPINS":
                    let pins = try parsePins()
                    commonInputPin = pins.input
                    commonOutputPin = pins.output
                case "FLOATING", "ORDERED":
                    while current != "+", current != "-", current != "END",
                          !current.isEmpty {
                        let instanceName = advance()
                        let pins: (input: String, output: String)
                        if current == "(" {
                            pins = try parsePins()
                        } else if let commonInputPin, let commonOutputPin {
                            pins = (commonInputPin, commonOutputPin)
                        } else {
                            throw OpenROADDFTScanImportError.scanDEFInvalid(
                                "instance \(instanceName) has no scan access pins"
                            )
                        }
                        elements.append(OpenROADScanDEFElement(
                            instanceName: instanceName,
                            scanInPinName: pins.input,
                            scanOutPinName: pins.output
                        ))
                    }
                default:
                    throw OpenROADDFTScanImportError.scanDEFInvalid(
                        "unsupported SCANCHAINS section \(section)"
                    )
                }
            }
            guard let startSignal, let stopSignal, let domainID,
                  !chainID.isEmpty, !elements.isEmpty else {
                throw OpenROADDFTScanImportError.scanDEFInvalid(
                    "chain \(chainID) is incomplete"
                )
            }
            return OpenROADScanDEFChain(
                chainID: chainID,
                startSignal: startSignal,
                stopSignal: stopSignal,
                domainID: domainID,
                elements: elements
            )
        }

        mutating func parseTopLevelEndpoint(_ label: String) throws -> String {
            guard advance() == "PIN" else {
                throw OpenROADDFTScanImportError.scanDEFInvalid(
                    "\(label) must be a top-level PIN"
                )
            }
            return try readValue("\(label) pin")
        }

        mutating func parsePins() throws -> (input: String, output: String) {
            try expect("(")
            try expect("IN")
            let input = try readValue("scan input pin")
            try expect(")")
            try expect("(")
            try expect("OUT")
            let output = try readValue("scan output pin")
            try expect(")")
            return (input, output)
        }
    }
}

struct OpenROADScanDEFChain: Sendable, Hashable {
    let chainID: String
    let startSignal: String
    let stopSignal: String
    let domainID: String
    let elements: [OpenROADScanDEFElement]
}

struct OpenROADScanDEFElement: Sendable, Hashable {
    let instanceName: String
    let scanInPinName: String
    let scanOutPinName: String
}
