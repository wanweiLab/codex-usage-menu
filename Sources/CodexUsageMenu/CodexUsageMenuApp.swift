import SwiftUI

@main
struct CodexUsageMenuApp: App {
    @StateObject private var usageService = CodexUsageService()
    @StateObject private var reminderService = ReminderService()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(
                service: usageService,
                reminderService: reminderService
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.donut")
                Text(usageService.menuBarText)
                    .monospacedDigit()
            }
            .accessibilityLabel(usageService.menuBarAccessibilityLabel)
            .task {
                usageService.start()
                reminderService.start()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
