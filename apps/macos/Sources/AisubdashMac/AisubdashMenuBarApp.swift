#if os(macOS)
import AppKit
import SwiftUI
import AisubdashCore

@MainActor
final class MenuBarLifecycle: NSObject, NSApplicationDelegate {
    let store = DashboardStore()
    private var updates: Task<Void, Never>?
    private var clockUpdates: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clockUpdates = Task {
            while !Task.isCancelled {
                store.tick()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
            }
        }
        updates = Task {
            while !Task.isCancelled {
                await store.reload()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        updates?.cancel()
        clockUpdates?.cancel()
    }
}

@MainActor
struct AisubdashMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarLifecycle.self) private var lifecycle

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: lifecycle.store)
        } label: {
            MenuBarLabelView(store: lifecycle.store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabelView: View {
    let store: DashboardStore

    var body: some View {
        // A TimelineView in a MenuBarExtra label hides the status item on macOS 27.2.
        // The store clock ticks every 30 s, so stale markers age without a new snapshot.
        let now = store.clock
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            if let labelText = labelText(now: now) {
                Text(labelText)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText(now: now))
    }

    private func labelText(now: Date) -> String? {
        switch store.pinnedQuotaState(now: now) {
        case .none:
            return nil
        case .unavailable:
            return "Pin: No Data"
        case .missing:
            return "Pin: Missing"
        case .available(_, let quota, let isStale):
            let formatted = QuotaFormatter.compactValue(quota)
            return isStale ? "\(formatted) (Stale)" : formatted
        }
    }

    private func accessibilityText(now: Date) -> String {
        switch store.pinnedQuotaState(now: now) {
        case .none:
            return "aisubdash usage monitor"
        case .unavailable:
            return "aisubdash, pinned quota data unavailable"
        case .missing:
            return "aisubdash, pinned quota missing"
        case .available(let account, let quota, let isStale):
            let formatted = QuotaFormatter.compactValue(quota)
            let stalePart = isStale ? ", stale" : ""
            return "aisubdash, \(account.name) \(quota.label) \(formatted)\(stalePart)"
        }
    }
}

#endif
