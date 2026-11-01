import Foundation

/// JSON coders configured for the core-services (FastAPI / Pydantic v2) wire format.
///
/// - Keys are snake_case on the wire; Swift properties are camelCase.
/// - Datetimes are ISO-8601, with or without fractional seconds, with or
///   without a UTC offset (naive values are treated as UTC, matching the
///   backend's storage convention).
/// - `date` fields are plain `YYYY-MM-DD` — model them as `CalendarDate`.
public enum JSONCoding {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = FlexibleISO8601.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised datetime format"
            )
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(FlexibleISO8601.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// Thread-safe ISO-8601 parsing that tolerates the variants Pydantic emits.
public enum FlexibleISO8601 {
    // ISO8601DateFormatter is documented as thread-safe for formatting/parsing
    // once configured, but is not `Sendable`; isolate behind nonisolated(unsafe).
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func date(from raw: String) -> Date? {
        if let d = withFraction.date(from: raw) ?? plain.date(from: raw) { return d }
        // Naive datetime (no offset) → interpret as UTC.
        let normalised = normaliseFraction(raw) + "Z"
        return withFraction.date(from: normalised) ?? plain.date(from: raw + "Z")
    }

    public static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    /// ISO8601DateFormatter only accepts up to 3 fractional digits on some OS
    /// versions; Python emits 6 (microseconds). Truncate to milliseconds.
    private static func normaliseFraction(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: ".") else { return raw + ".000" }
        let fraction = raw[raw.index(after: dot)...].prefix { $0.isNumber }
        let ms = String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return String(raw[..<dot]) + "." + ms
    }
}

/// A calendar day with no time component (`date` in Pydantic).
public struct CalendarDate: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public init?(iso raw: String) {
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = CalendarDate(iso: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: expected YYYY-MM-DD")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Pydantic v2 serialises `Decimal` as a JSON string ("1.50") by default, but
/// some endpoints emit numbers. Accept both; expose as `Decimal`.
public struct FlexibleDecimal: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let value: Decimal

    public init(_ value: Decimal) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let parsed = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid decimal string")
            }
            value = parsed
        } else {
            value = try container.decode(Decimal.self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: value).stringValue)
    }

    public var doubleValue: Double { NSDecimalNumber(decimal: value).doubleValue }
    public var description: String { NSDecimalNumber(decimal: value).stringValue }

    public static func < (lhs: FlexibleDecimal, rhs: FlexibleDecimal) -> Bool { lhs.value < rhs.value }
}
