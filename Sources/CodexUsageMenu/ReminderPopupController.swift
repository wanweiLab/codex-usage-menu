import AppKit
import Combine
import SwiftUI

@MainActor
final class ReminderPopupController: ReminderPresenting {
    static let shared = ReminderPopupController()

    private var panel: NSPanel?
    private var countdownTask: Task<Void, Never>?
    private var pendingKinds: [ReminderKind] = []
    private var currentKind: ReminderKind?

    func present(_ kind: ReminderKind) {
        guard panel == nil else {
            if kind != currentKind, !pendingKinds.contains(kind) {
                pendingKinds.append(kind)
            }
            return
        }

        showPopup(for: kind)
    }

    private func showPopup(for kind: ReminderKind) {
        currentKind = kind
        let model = ReminderPopupModel(kind: kind, remainingSeconds: 60)
        model.onClose = { [weak self] in
            self?.dismissCurrentPopup()
        }

        let size = NSSize(width: 460, height: 220)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: ReminderPopupView(model: model))
        panel.setFrameOrigin(Self.popupOrigin(for: size))

        self.panel = panel
        panel.orderFrontRegardless()

        countdownTask?.cancel()
        countdownTask = Task { [weak self, weak model] in
            for remaining in stride(from: 59, through: 0, by: -1) {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                guard !Task.isCancelled, let self, let model else { return }
                model.remainingSeconds = remaining
                if remaining == 0 {
                    self.dismissCurrentPopup()
                    return
                }
            }
        }
    }

    private func dismissCurrentPopup() {
        countdownTask?.cancel()
        countdownTask = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        currentKind = nil

        guard !pendingKinds.isEmpty else { return }
        let nextKind = pendingKinds.removeFirst()
        showPopup(for: nextKind)
    }

    private static func popupOrigin(for size: NSSize) -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? .zero
        return NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
    }
}

@MainActor
private final class ReminderPopupModel: ObservableObject {
    let kind: ReminderKind
    @Published var remainingSeconds: Int
    var onClose: (() -> Void)?

    init(kind: ReminderKind, remainingSeconds: Int) {
        self.kind = kind
        self.remainingSeconds = remainingSeconds
    }

    func close() {
        onClose?()
    }
}

private struct ReminderPopupView: View {
    @ObservedObject var model: ReminderPopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(CodexTheme.accent.opacity(0.12))
                    Image(systemName: model.kind.systemImage)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(CodexTheme.accent)
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(model.kind.popupTitle)
                        .font(.system(size: 18, weight: .semibold))
                    Text(model.kind.popupBody)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    model.close()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("关闭提醒")
                .accessibilityLabel("关闭提醒")
            }

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("60 秒后自动关闭")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    ProgressView(value: Double(60 - model.remainingSeconds), total: 60)
                        .progressViewStyle(.linear)
                        .tint(CodexTheme.accent)
                        .accessibilityLabel("自动关闭倒计时")
                        .accessibilityValue("还剩 \(model.remainingSeconds) 秒")
                }

                Text("\(model.remainingSeconds) 秒")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)

                Button("关闭") {
                    model.close()
                }
                .controlSize(.regular)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460, height: 220)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
