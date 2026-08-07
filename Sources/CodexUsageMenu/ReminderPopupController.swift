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

        let size = NSSize(width: 360, height: 360)
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
        panel.hasShadow = false
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(CodexTheme.accent.opacity(0.12))
                    Image(systemName: model.kind.systemImage)
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(CodexTheme.accent)
                }
                .frame(width: 68, height: 68)
                .accessibilityHidden(true)

                Text(model.kind.popupTitle)
                    .font(.system(size: 21, weight: .semibold))
                    .padding(.top, 13)

                Text(model.kind.popupBody)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 270)
                    .padding(.top, 5)

                countdownRing
                    .padding(.top, 20)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                model.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .help("关闭提醒")
            .accessibilityLabel("关闭提醒")
        }
        .frame(width: 360, height: 360)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(CodexTheme.accent.opacity(0.13), lineWidth: 8)

            Circle()
                .trim(from: 0, to: Double(model.remainingSeconds) / 60)
                .stroke(
                    CodexTheme.accent,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.25),
                    value: model.remainingSeconds
                )

            VStack(spacing: 0) {
                Text("\(model.remainingSeconds)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("秒后关闭")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 102, height: 102)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("自动关闭倒计时")
        .accessibilityValue("还剩 \(model.remainingSeconds) 秒")
    }
}
