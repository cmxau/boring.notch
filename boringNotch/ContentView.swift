//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var agentHub = AgentHub.shared
    @ObservedObject var eventNotifier = CalendarEventNotifier.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?


    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace


    @Default(.showNotchPet) var showNotchPet

    /// The pointer is over the notch pet, which mustn't open the notch on hover so the cat can be clicked.
    @State private var isHoveringPet = false

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    /// On the lock screen only the padlock is shown, unless the user opted into the full notch there.
    private var isLockScreenRestricted: Bool {
        coordinator.lockScreenIndicator == .locked && !Defaults[.showOnLockScreen]
    }

    private var lockIndicatorSlotSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var accessoryArtworkSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 4)
    }

    /// Both sides of the accessory indicator share this width so the notch stays centred under the camera.
    private var accessoryWingWidth: CGFloat {
        max(accessoryArtworkSize, 66)
    }

    private var petSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 4)
    }

    private var petWingWidth: CGFloat {
        petSize * NotchPetClip.aspectRatio
    }

    /// The mirror fills the open notch while it's on, hiding the notch's usual contents.
    private var showsMirror: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    /// The pet keeps the closed notch company when nothing else is showing.
    private var showsPet: Bool {
        showNotchPet && !coordinator.expandingView.show && vm.notchState == .closed
            && !musicManager.isPlaying && musicManager.isPlayerIdle && !vm.hideOnClosed
    }

    /// Room either side of the camera for an upcoming calendar event's title and time.
    private let eventWingWidth: CGFloat = 110

    /// What the closed notch shows for AI agents, if anything.
    private var agentActivity: (kind: AgentKind, status: AgentStatus, label: String)? {
        guard Defaults[.agentShowInClosedNotch], Defaults[.agentIntegrationEnabled] else { return nil }
        if let request = agentHub.requests.first {
            return (request.agent, .waitingForApproval, "Needs you")
        }
        if let waiting = agentHub.activeSessions.first(where: { $0.status.needsAttention }) {
            return (waiting.kind, waiting.status, "Needs you")
        }
        if let finished = agentHub.recentlyFinished {
            return (finished.kind, .finished, "Done")
        }
        let working = agentHub.activeSessions
        guard let first = working.first else { return nil }
        return (first.kind, .working, working.count > 1 ? "\(working.count) working" : "Working")
    }

    /// Agents waiting on the user, or just finished, take priority over other closed-notch activities.
    private var agentActivityIsUrgent: Bool {
        guard let status = agentActivity?.status else { return false }
        return status != .working
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.lockScreenIndicator != .hidden && vm.notchState == .closed {
            chinWidth += (2 * lockIndicatorSlotSize + 20)
        } else if coordinator.accessoryIndicator != nil && vm.notchState == .closed {
            chinWidth += (2 * accessoryWingWidth + 20)
        } else if eventNotifier.alert != nil && vm.notchState == .closed {
            chinWidth += (2 * eventWingWidth + 20)
        } else if agentActivityIsUrgent && vm.notchState == .closed {
            chinWidth += (2 * accessoryWingWidth + 20)
        } else if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if agentActivity != nil && vm.notchState == .closed && !vm.hideOnClosed {
            chinWidth += (2 * accessoryWingWidth + 20)
        } else if showsPet {
            chinWidth += (2 * petWingWidth + 20)
        }

        return chinWidth
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    // The open notch is as wide as the closed notch playing music, plus room for the header
                    .frame(width: vm.notchState == .open ? vm.notchSize.width : nil)
                    .background(NotchBackgroundView(isOpen: vm.notchState == .open || coordinator.helloAnimationRunning))
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        Divider()
                        Button("Restart Boring Notch") {
                            ApplicationRelauncher.restart()
                        }
                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                        .keyboardShortcut(KeyEquivalent("q"), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    // Just tall enough for the lettering, below the camera
                    let helloWidth = getClosedNotchSize().width
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: helloWidth,
                        height: helloWidth * HelloShape.aspectRatio
                    )
                    .padding(.top, vm.effectiveClosedNotchHeight + 4)
                    .padding(.bottom, 10)
                } else {
                    if coordinator.lockScreenIndicator != .hidden && vm.notchState == .closed {
                        LockIndicatorActivity()
                    } else if let accessory = coordinator.accessoryIndicator, vm.notchState == .closed {
                        AccessoryConnectedActivity(accessory)
                    } else if let alert = eventNotifier.alert, vm.notchState == .closed {
                        CalendarEventActivity(alert)
                    } else if agentActivityIsUrgent, let activity = agentActivity, vm.notchState == .closed {
                        AgentLiveActivity(activity)
                    } else if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if let activity = agentActivity, vm.notchState == .closed && !vm.hideOnClosed {
                          AgentLiveActivity(activity)
                      } else if showsPet {
                          NotchPetActivity()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                  }
              }
              .conditionalModifier(coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed)) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    if showsMirror {
                        NotchMirrorView(webcamManager: webcamManager)
                            .transition(.opacity)
                    } else {
                        // A tab hidden since it was last open falls back to Home
                        switch isTabAvailable(coordinator.currentView) ? coordinator.currentView : .home {
                        case .home:
                            NotchHomeView(albumArtNamespace: albumArtNamespace)
                        case .music:
                            MusicTabView(albumArtNamespace: albumArtNamespace)
                        case .calendar:
                            CalendarTabView()
                        case .shelf:
                            ShelfView()
                        case .agents:
                            AgentsView()
                        }
                    }
                }
                .animation(.smooth(duration: 0.25), value: showsMirror)
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func LockIndicatorActivity() -> some View {
        HStack {
            LockScreenAnimation(
                isUnlocked: coordinator.lockScreenIndicator == .unlocked,
                size: lockIndicatorSlotSize * 1.25
            )
            .frame(width: lockIndicatorSlotSize, height: lockIndicatorSlotSize)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            // Mirrors the padlock's width so the notch stays centred under the camera
            Rectangle()
                .fill(.clear)
                .frame(width: lockIndicatorSlotSize, height: lockIndicatorSlotSize)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    func AccessoryConnectedActivity(_ accessory: ConnectedAccessory) -> some View {
        HStack {
            AccessoryArtworkView(artwork: accessory.artwork, size: accessoryArtworkSize)
                .id(accessory.id)
                .frame(width: accessoryWingWidth, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Text("Connected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .frame(width: accessoryWingWidth, alignment: .trailing)
                .transition(.opacity)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessory.name) connected")
    }

    @ViewBuilder
    func CalendarEventActivity(_ alert: CalendarEventAlert) -> some View {
        let tint = Color(nsColor: alert.event.calendar.color)
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(alert.event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: eventWingWidth, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Group {
                if alert.moment == .now {
                    Text("Now")
                } else {
                    Text(alert.event.start, style: .relative)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .monospacedDigit()
            .frame(width: eventWingWidth, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(alert.moment == .now ? "\(alert.event.title) is starting" : "\(alert.event.title) starts soon")
    }

    @ViewBuilder
    func AgentLiveActivity(_ activity: (kind: AgentKind, status: AgentStatus, label: String)) -> some View {
        HStack {
            AgentStatusIcon(kind: activity.kind, status: activity.status, size: max(0, vm.effectiveClosedNotchHeight - 12))
                .frame(width: accessoryWingWidth, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Text(activity.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activity.status.tint)
                .lineLimit(1)
                .fixedSize()
                .frame(width: accessoryWingWidth, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.kind.displayName): \(activity.label)")
    }

    @ViewBuilder
    func NotchPetActivity() -> some View {
        HStack {
            NotchPetView(
                size: petSize,
                onOtherTap: { doOpen() },
                onHover: { hovering in
                    isHoveringPet = hovering
                    guard !hovering else { return }
                    // Moving from the cat to the rest of the notch opens it as if the pointer had just arrived.
                    // Waits until a move off the notch altogether has cleared `isHovering`.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        if isHovering && !isHoveringPet && vm.notchState == .closed {
                            scheduleHoverOpen()
                        }
                    }
                }
            )
            .frame(width: petWingWidth, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            // Mirrors the pet's width so the notch stays centred under the camera
            Rectangle()
                .fill(.clear)
                .frame(width: petWingWidth, height: petSize)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onDisappear { isHoveringPet = false }
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                   )
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                       )
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                       )
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                Rectangle()
                    .fill(
                        Defaults[.coloredSpectrogram]
                            ? Color(nsColor: musicManager.avgColor).gradient
                            : Color.gray.gradient
                    )
                    .frame(width: 50, alignment: .center)
                    .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                    .mask {
                        AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                            .frame(width: 16, height: 12)
                    }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        if isLockScreenRestricted { return }
        // Tapping the notch while an agent is waiting goes straight to what it's waiting for
        if agentActivityIsUrgent {
            coordinator.currentView = .agents
        }
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch || coordinator.helloAnimationRunning || isLockScreenRestricted { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            scheduleHoverOpen()
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    /// Opens the notch once the pointer has rested on it long enough, unless it's on the pet.
    private func scheduleHoverOpen() {
        guard vm.notchState == .closed,
              !coordinator.sneakPeek.show,
              Defaults[.openNotchOnHover] else { return }

        hoverTask?.cancel()
        hoverTask = Task {
            try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.vm.notchState == .closed,
                      self.isHovering,
                      !self.isHoveringPet,
                      !self.coordinator.sneakPeek.show else { return }

                self.doOpen()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
