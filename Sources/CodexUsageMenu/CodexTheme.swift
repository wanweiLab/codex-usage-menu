import SwiftUI

enum CodexTheme {
    static let accent = Color(red: 0.14, green: 0.56, blue: 0.77)
    static let accentLight = Color(red: 0.33, green: 0.71, blue: 0.88)
    static let card = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let secondaryCard = Color(nsColor: .underPageBackgroundColor).opacity(0.72)
    static let border = Color.primary.opacity(0.09)
    static let secondaryText = Color.secondary
    static let panelWidth: CGFloat = 354
    static let panelContentHeight: CGFloat = 354
    static let panelHeight: CGFloat = 482
}
