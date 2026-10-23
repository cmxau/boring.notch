//
//  AgentSoundSettings.swift
//  boringNotch
//
//  Agent sound alerts and sound packs.
//

import Defaults
import SwiftUI

struct AgentSoundSettingsSection: View {
    var body: some View {
        Section {
            Defaults.Toggle(key: .agentSoundsEnabled) {
                Text("Play sounds")
            }
        } header: {
            Text("Sounds")
        }
    }
}
