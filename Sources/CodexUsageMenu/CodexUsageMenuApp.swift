import SwiftUI

@main
struct CodexUsageMenuApp: App {
    @StateObject private var usageService = CodexUsageService()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(service: usageService)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.donut")
                Text(usageService.menuBarText)
                    .monospacedDigit()
            }
            .accessibilityLabel(usageService.menuBarAccessibilityLabel)
            .task {
                usageService.start()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
