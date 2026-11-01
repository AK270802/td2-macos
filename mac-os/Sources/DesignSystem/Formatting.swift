import Foundation
import EffiLensKit

/// Display formatting helpers. Pure presentation — no business rules.
enum Format {
    /// 3h 25m / 45m / 0m.
    static func duration(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// 1:02:03 for live timers.
    static func clock(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    static func hours(_ seconds: Int, fractionDigits: Int = 1) -> String {
        (Double(seconds) / 3600).formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// Leave day quantities keep up to one decimal (half days).
    static func days(_ value: FlexibleDecimal?) -> String {
        guard let value else { return "—" }
        return value.doubleValue.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func shortDate(_ day: CalendarDate) -> String {
        guard let date = day.date() else { return day.description }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func dateRange(_ start: CalendarDate, _ end: CalendarDate) -> String {
        start == end ? shortDate(start) : "\(shortDate(start)) – \(shortDate(end))"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}
