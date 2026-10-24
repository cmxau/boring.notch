//
//  CalendarEventNotifier.swift
//  boringNotch
//
//  Shows upcoming calendar events in the closed notch: a few minutes before they start (5 by default), and again
//  when they start.
//

import Combine
import Defaults
import Foundation

struct CalendarEventAlert: Equatable, Identifiable {
    enum Moment: Equatable {
        case soon
        case now
    }

    let event: EventModel
    let moment: Moment

    var id: String { event.id + (moment == .now ? ":now" : ":soon") }
}

@MainActor
final class CalendarEventNotifier: ObservableObject {
    static let shared = CalendarEventNotifier()

    /// The alert showing in the notch right now, if any.
    @Published private(set) var alert: CalendarEventAlert?

    /// Alerts already shown, so each one shows once.
    private var shown: Set<String> = []
    private var loop: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    private static let alertDuration: Duration = .seconds(8)
    private static let checkInterval: Duration = .seconds(30)

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        alert = nil
    }

    private func check() async {
        guard Defaults[.calendarEventNotifications] else { return }
        let now = Date()
        let lead = TimeInterval(Defaults[.calendarEventLeadMinutes] * 60)
        // Events that started in the last minute still get their "now" alert
        let events = await CalendarManager.shared.timedEvents(
            startingFrom: now.addingTimeInterval(-60),
            to: now.addingTimeInterval(lead + 1)
        )

        for event in events.sorted(by: { $0.start < $1.start }) {
            let moment: CalendarEventAlert.Moment = event.start <= now.addingTimeInterval(30) ? .now : .soon
            let candidate = CalendarEventAlert(event: event, moment: moment)
            guard !shown.contains(candidate.id) else { continue }
            shown.insert(candidate.id)
            if moment == .now {
                // Starting now covers the earlier reminder too
                shown.insert(event.id + ":soon")
            }
            show(candidate)
            break
        }

        // Forget alerts for events long gone
        if shown.count > 200 {
            shown.removeAll()
        }
    }

    private func show(_ newAlert: CalendarEventAlert) {
        alert = newAlert
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.alertDuration)
            guard !Task.isCancelled else { return }
            self?.alert = nil
        }
    }
}
