enum STILToken: Equatable {
    case word(String)
    case quoted(String)
    case singleQuoted(String)
    case leftBrace
    case rightBrace
    case semicolon
    case equal
}
