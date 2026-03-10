import Foundation

let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

let isoFormatterNoFrac: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm:ss a"
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    return formatter
}()

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter
}()

func formatReset(_ isoString: String) -> String {
    if let date = isoFormatter.date(from: isoString) {
        return formatResetDate(date)
    }
    if let date = isoFormatterNoFrac.date(from: isoString) {
        return formatResetDate(date)
    }
    return "?"
}

func formatResetDate(_ date: Date) -> String {
    let diff = date.timeIntervalSince(Date())
    if diff < 0 {
        return "now"
    }

    let hours = Int(diff) / 3600
    let minutes = (Int(diff) % 3600) / 60

    if hours == 0 {
        return "\(minutes)m"
    } else if hours < 24 {
        return "\(hours)h \(minutes)m"
    } else {
        return dateFormatter.string(from: date)
    }
}
