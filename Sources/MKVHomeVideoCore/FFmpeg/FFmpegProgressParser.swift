import Foundation

public enum FFmpegProgressEvent: Sendable, Equatable {
    case updated(fraction: Double)
    case completed
}

public struct FFmpegProgressParser: Sendable {
    private let totalDurationMicroseconds: Int64?
    private var remainder = ""
    private var record: [String: String] = [:]

    public init(totalDurationMicroseconds: Int64?) {
        self.totalDurationMicroseconds = totalDurationMicroseconds
    }

    public mutating func feed(_ chunk: String) -> [FFmpegProgressEvent] {
        remainder += chunk
        var events: [FFmpegProgressEvent] = []

        while let newline = remainder.firstIndex(of: "\n") {
            let line = String(remainder[..<newline]).trimmingCharacters(in: .newlines)
            remainder.removeSubrange(...newline)
            guard let separator = line.firstIndex(of: "=") else { continue }

            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            record[key] = value

            guard key == "progress" else { continue }
            if value == "end" {
                events.append(.completed)
            } else if let fraction = fractionFromCurrentRecord() {
                events.append(.updated(fraction: fraction))
            }
            record.removeAll(keepingCapacity: true)
        }

        return events
    }

    private func fractionFromCurrentRecord() -> Double? {
        guard let totalDurationMicroseconds, totalDurationMicroseconds > 0 else { return nil }
        let value = record["out_time_ms"] ?? record["out_time_us"]
        guard let microseconds = value.flatMap(Int64.init) else { return nil }
        return min(1, max(0, Double(microseconds) / Double(totalDurationMicroseconds)))
    }
}
