import Foundation

struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let usedPercent: Int
    let durationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Int {
        max(0, 100 - usedPercent)
    }

    var isWeekly: Bool {
        guard let durationMinutes else { return false }
        return durationMinutes >= 6 * 24 * 60
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let windows: [UsageWindow]
    let planType: String?
    let updatedAt: Date

    var weeklyWindow: UsageWindow? {
        windows.first(where: \.isWeekly)
            ?? windows.max(by: { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) })
    }

    var shortWindow: UsageWindow? {
        let weeklyID = weeklyWindow?.id
        return windows
            .filter { $0.id != weeklyID }
            .min(by: { ($0.durationMinutes ?? .max) < ($1.durationMinutes ?? .max) })
    }
}

struct CodexAccount: Equatable, Sendable {
    let email: String?
    let planType: String?
    let type: String
}

enum UsageLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
