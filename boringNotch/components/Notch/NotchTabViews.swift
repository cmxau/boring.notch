//
//  NotchTabViews.swift
//  boringNotch
//
//  The Music tab (player on the left, lyrics on the right) and the Calendar tab (the month on the left, the
//  selected day's events on the right).
//

import Defaults
import SwiftUI

// MARK: - Music

struct MusicTabView: View {
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            LyricsPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The song's lyrics, following along with the music when they're synced.
struct LyricsPanel: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        Group {
            if musicManager.isFetchingLyrics {
                message("Loading lyrics…")
            } else if !musicManager.syncedLyrics.isEmpty {
                syncedLyrics
            } else if !musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(musicManager.currentLyrics)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                message(musicManager.songTitle.isEmpty ? "Play something to see its lyrics" : "No lyrics found")
            }
        }
        .padding(.top, 6)
    }

    private var syncedLyrics: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let current = currentLineIndex(at: timeline.date)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(musicManager.syncedLyrics.enumerated()), id: \.offset) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: index == current ? 14 : 12, weight: index == current ? .bold : .medium))
                                .foregroundStyle(index == current ? .white : .gray.opacity(index < current ? 0.5 : 0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 40)
                }
                .onChange(of: current) { _, line in
                    withAnimation(.smooth(duration: 0.4)) {
                        proxy.scrollTo(line, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(current, anchor: .center)
                }
            }
        }
        .mask(
            LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    private func currentLineIndex(at date: Date) -> Int {
        let elapsed: Double = {
            guard musicManager.isPlaying else { return musicManager.elapsedTime }
            let delta = date.timeIntervalSince(musicManager.timestampDate)
            return min(max(musicManager.elapsedTime + delta * musicManager.playbackRate, 0), musicManager.songDuration)
        }()
        return musicManager.syncedLyrics.lastIndex { $0.time <= elapsed } ?? 0
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "quote.bubble")
                .font(.title2)
                .foregroundStyle(.gray)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Calendar

struct CalendarTabView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MonthGridView(selectedDate: $selectedDate)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                if EventListView.filteredEvents(events: calendarManager.events).isEmpty {
                    EmptyEventsView(selectedDate: selectedDate)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EventListView(events: calendarManager.events)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 4)
        .onHover { vm.isHoveringCalendar = $0 }
        .task(id: selectedDate) {
            await calendarManager.updateCurrentDate(selectedDate)
        }
    }
}

/// A month of days to pick from, with arrows to move between months.
struct MonthGridView: View {
    @Binding var selectedDate: Date
    @State private var month = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.gray)

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.gray)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 15)
                    }
                }
            }
        }
        .onAppear { month = selectedDate }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        return Button {
            selectedDate = day
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 10, weight: isToday || isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? .white : (isToday ? Color.effectiveAccent : .white.opacity(0.85)))
                .frame(maxWidth: .infinity)
                .frame(height: 15)
                .background {
                    if isSelected {
                        Capsule().fill(Color.effectiveAccent)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Very short weekday names, starting on the user's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month's days, with nils before the first day so it lands under its weekday.
    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let dates = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: leading) + dates
    }

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: month) {
            month = newMonth
        }
    }
}
