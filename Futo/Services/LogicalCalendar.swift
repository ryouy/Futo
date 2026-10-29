import Foundation

/// 「日」の区切りを午前4時にする暦。深夜（0〜4時）の記録は前日に数える。
/// 例：23日 1:30 の操作は「23日の夜」に属さず、「22日」の記録として扱う。
struct LogicalCalendar {
    var calendar: Calendar
    var dayStartHour = 4

    init(calendar: Calendar = .current, dayStartHour: Int = 4) {
        self.calendar = calendar
        self.dayStartHour = dayStartHour
    }

    private func shifted(_ date: Date) -> Date {
        calendar.date(byAdding: .hour, value: -dayStartHour, to: date) ?? date
    }

    /// 論理日の識別子（例：2027-01-15）
    func dayKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: shifted(date))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// その日（論理日）の範囲。午前4時から翌午前4時まで。
    func dayInterval(containing date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: shifted(date))
        let begin = calendar.date(byAdding: .hour, value: dayStartHour, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: 1, to: begin) ?? begin.addingTimeInterval(86_400)
        return DateInterval(start: begin, end: end)
    }

    func previousDayInterval(before date: Date) -> DateInterval {
        let today = dayInterval(containing: date)
        return dayInterval(containing: today.start.addingTimeInterval(-1))
    }

    /// 今週（暦の週。論理日で数える）。
    func weekInterval(containing date: Date) -> DateInterval {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: shifted(date)) else {
            return dayInterval(containing: date)
        }
        let start = calendar.date(byAdding: .hour, value: dayStartHour, to: week.start) ?? week.start
        let end = calendar.date(byAdding: .hour, value: dayStartHour, to: week.end) ?? week.end
        return DateInterval(start: start, end: end)
    }

    /// 今月（暦の月。論理日で数える）。
    func monthInterval(containing date: Date) -> DateInterval {
        guard let month = calendar.dateInterval(of: .month, for: shifted(date)) else {
            return dayInterval(containing: date)
        }
        let start = calendar.date(byAdding: .hour, value: dayStartHour, to: month.start) ?? month.start
        let end = calendar.date(byAdding: .hour, value: dayStartHour, to: month.end) ?? month.end
        return DateInterval(start: start, end: end)
    }

    func previousWeekInterval(before date: Date) -> DateInterval {
        weekInterval(containing: weekInterval(containing: date).start.addingTimeInterval(-1))
    }

    /// 論理日の午前4時を0とした分。時刻設定が「その日のどこか」を比べるために使う。
    func logicalMinute(of date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return logicalMinute(clockMinute: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    func logicalMinute(clockMinute: Int) -> Int {
        (clockMinute - dayStartHour * 60 + 1440) % 1440
    }

    /// 0時からの分（0〜1439）
    func clockMinute(of date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// 指定した日の「時:分」の日時。その日の暦日で作る。
    func date(on day: Date, clockMinute: Int) -> Date? {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: clockMinute, to: start)
    }
}
