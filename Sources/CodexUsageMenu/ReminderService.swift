import Combine
import Foundation

enum ReminderKind: String, CaseIterable, Hashable, Sendable {
    case sedentary
    case hydration

    var title: String {
        switch self {
        case .sedentary: "久坐提醒"
        case .hydration: "喝水提醒"
        }
    }

    var popupTitle: String {
        switch self {
        case .sedentary: "该起来活动一下了"
        case .hydration: "该喝水了"
        }
    }

    var popupBody: String {
        switch self {
        case .sedentary: "站起来走动几分钟，放松肩颈和眼睛。"
        case .hydration: "补充一点水分，休息一下再继续。"
        }
    }

    var systemImage: String {
        switch self {
        case .sedentary: "figure.stand"
        case .hydration: "drop.fill"
        }
    }

    var defaultIntervalMinutes: Int {
        switch self {
        case .sedentary: 60
        case .hydration: 45
        }
    }
}

struct ReminderConfiguration: Equatable, Sendable {
    let isEnabled: Bool
    let intervalMinutes: Int
}

@MainActor
protocol ReminderPresenting: AnyObject {
    func present(_ kind: ReminderKind)
}

@MainActor
final class ReminderService: ObservableObject {
    static let minimumIntervalMinutes = 1
    static let maximumIntervalMinutes = 720

    @Published private(set) var sedentaryConfiguration: ReminderConfiguration
    @Published private(set) var hydrationConfiguration: ReminderConfiguration

    private let presenter: any ReminderPresenting
    private let defaults: UserDefaults
    private let secondsPerMinute: Double
    private var reminderTasks: [ReminderKind: Task<Void, Never>] = [:]
    private var hasStarted = false

    convenience init() {
        self.init(presenter: ReminderPopupController.shared)
    }

    init(
        presenter: any ReminderPresenting,
        defaults: UserDefaults = .standard,
        secondsPerMinute: Double = 60
    ) {
        self.presenter = presenter
        self.defaults = defaults
        self.secondsPerMinute = secondsPerMinute
        sedentaryConfiguration = Self.loadConfiguration(for: .sedentary, defaults: defaults)
        hydrationConfiguration = Self.loadConfiguration(for: .hydration, defaults: defaults)
    }

    deinit {
        for task in reminderTasks.values {
            task.cancel()
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        for kind in ReminderKind.allCases where configuration(for: kind).isEnabled {
            schedule(for: kind)
        }
    }

    func configuration(for kind: ReminderKind) -> ReminderConfiguration {
        switch kind {
        case .sedentary: sedentaryConfiguration
        case .hydration: hydrationConfiguration
        }
    }

    func setEnabled(_ isEnabled: Bool, for kind: ReminderKind) {
        let current = configuration(for: kind)
        updateConfiguration(
            ReminderConfiguration(
                isEnabled: isEnabled,
                intervalMinutes: current.intervalMinutes
            ),
            for: kind
        )

        if isEnabled {
            schedule(for: kind)
        } else {
            reminderTasks[kind]?.cancel()
            reminderTasks[kind] = nil
        }
    }

    func updateInterval(_ intervalMinutes: Int, for kind: ReminderKind) {
        let clampedInterval = Self.clampedInterval(intervalMinutes)
        let current = configuration(for: kind)
        let intervalChanged = clampedInterval != current.intervalMinutes

        updateConfiguration(
            ReminderConfiguration(
                isEnabled: current.isEnabled,
                intervalMinutes: clampedInterval
            ),
            for: kind
        )

        if current.isEnabled, intervalChanged {
            schedule(for: kind)
        }
    }

    private func schedule(for kind: ReminderKind) {
        reminderTasks[kind]?.cancel()
        reminderTasks[kind] = Task { [weak self] in
            while !Task.isCancelled {
                guard let configuration = self?.configuration(for: kind),
                      let secondsPerMinute = self?.secondsPerMinute else {
                    return
                }
                guard configuration.isEnabled else { return }

                do {
                    try await Task.sleep(
                        for: .seconds(
                            Double(configuration.intervalMinutes) * secondsPerMinute
                        )
                    )
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.presenter.present(kind)
            }
        }
    }

    private func updateConfiguration(
        _ configuration: ReminderConfiguration,
        for kind: ReminderKind
    ) {
        switch kind {
        case .sedentary:
            sedentaryConfiguration = configuration
        case .hydration:
            hydrationConfiguration = configuration
        }

        defaults.set(configuration.isEnabled, forKey: Self.enabledKey(for: kind))
        defaults.set(configuration.intervalMinutes, forKey: Self.intervalKey(for: kind))
    }

    private static func loadConfiguration(
        for kind: ReminderKind,
        defaults: UserDefaults
    ) -> ReminderConfiguration {
        let interval: Int
        if defaults.object(forKey: intervalKey(for: kind)) == nil {
            interval = kind.defaultIntervalMinutes
        } else {
            interval = clampedInterval(defaults.integer(forKey: intervalKey(for: kind)))
        }

        return ReminderConfiguration(
            isEnabled: defaults.bool(forKey: enabledKey(for: kind)),
            intervalMinutes: interval
        )
    }

    private static func clampedInterval(_ value: Int) -> Int {
        min(maximumIntervalMinutes, max(minimumIntervalMinutes, value))
    }

    private static func enabledKey(for kind: ReminderKind) -> String {
        "reminder.\(kind.rawValue).enabled"
    }

    private static func intervalKey(for kind: ReminderKind) -> String {
        "reminder.\(kind.rawValue).intervalMinutes"
    }
}
