struct ProcessingLogStateStore {
    static let visibleLineLimit = 80

    private(set) var lines: [String] = []

    var text: String {
        lines.joined(separator: "\n")
    }

    var visibleLines: [String] {
        Array(lines.suffix(Self.visibleLineLimit))
    }

    mutating func append(_ line: String) {
        lines.append(line)
    }

    mutating func reset() {
        lines.removeAll()
    }
}
