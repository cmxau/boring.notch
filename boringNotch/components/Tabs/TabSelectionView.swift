//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: String { label }
    let label: String
    let icon: String
    let view: NotchViews
}

/// Home first, then the other tabs in the order chosen in Settings, leaving out the ones turned off.
var tabs: [TabModel] {
    orderedTabViews.filter(isTabAvailable).map { TabModel(label: $0.title, icon: $0.icon, view: $0) }
}

/// Every tab after Home in the user's order, including any the saved order doesn't know about yet.
var orderedTabViews: [NotchViews] {
    var order = Defaults[.tabOrder].filter { $0 != .home }
    order += NotchViews.allCases.filter { $0 != .home && !order.contains($0) }
    return [.home] + order
}

func isTabAvailable(_ view: NotchViews) -> Bool {
    if view == .home { return true }
    if Defaults[.hiddenTabs].contains(view) { return false }
    switch view {
    case .home, .music: return true
    case .calendar: return Defaults[.showCalendar]
    case .agents: return Defaults[.agentIntegrationEnabled]
    case .shelf: return Defaults[.boringShelf]
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
