public enum DFTWaveformAction: String, Sendable, Hashable, Codable {
    case driveLow
    case driveHigh
    case driveHighImpedance
    case compareLow
    case compareHigh
    case mask
}
