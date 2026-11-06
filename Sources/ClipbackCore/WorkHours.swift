import Foundation

/// When captures default to the Work library: Monday to Friday, 10:00 to 18:00, local time.
public struct WorkHours: Sendable, Equatable {
    /// Calendar weekday numbers, Sunday = 1.
    public var weekdays: Set<Int>
    public var startHour: Int
    public var endHour: Int

    public init(weekdays: Set<Int>, startHour: Int, endHour: Int) {
        self.weekdays = weekdays
        self.startHour = startHour
        self.endHour = endHour
    }

    public static let standard = WorkHours(weekdays: [2, 3, 4, 5, 6], startHour: 10, endHour: 18)

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour else { return false }
        return weekdays.contains(weekday) && hour >= startHour && hour < endHour
    }

    public func library(at date: Date, calendar: Calendar = .current) -> Library {
        contains(date, calendar: calendar) ? .work : .personal
    }

    /// "Mon–Fri 10:00–18:00", for the menu.
    public var summary: String {
        "Mon–Fri \(String(format: "%02d:00", startHour))–\(String(format: "%02d:00", endHour))"
    }
}
