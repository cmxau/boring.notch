//
//  OpenNotchHUD.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-23.
//

import SwiftUI
import Defaults

struct OpenNotchHUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Default(.showOpenNotchHUDPercentage) var showPercentage
    
    var body: some View {
        // The header beside the camera is narrow; drop the percentage, then shorten the slider, before overflowing
        ViewThatFits(in: .horizontal) {
            hud(sliderWidth: showPercentage ? 65 : 108, showsPercentage: showPercentage)
            hud(sliderWidth: 60, showsPercentage: false)
            hud(sliderWidth: 36, showsPercentage: false)
        }
    }

    private func hud(sliderWidth: CGFloat, showsPercentage: Bool) -> some View {
        HStack(spacing: 6) {
            // Icon
            Group {
                switch type {
                case .volume:
                    if icon.isEmpty {
                        Image(systemName: SpeakerSymbol(value))
                            .contentTransition(.interpolate)
                    } else {
                        Image(systemName: icon)
                            .contentTransition(.interpolate)
                    }
                case .brightness:
                    Image(systemName: "sun.max.fill")
                        .contentTransition(.symbolEffect)
                case .backlight:
                    Image(systemName: value > 0.5 ? "light.max" : "light.min")
                        .contentTransition(.interpolate)
                case .mic:
                    Image(systemName: "mic")
                        .symbolVariant(value > 0 ? .none : .slash)
                        .contentTransition(.interpolate)
                default:
                    EmptyView()
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 20, alignment: .center)
            
            // Slider or Status Text
            if type != .mic {
                DraggableProgressBar(value: $value, onChange: { newVal in
                     updateSystemValue(newVal)
                })
                .frame(width: sliderWidth)
            } else {
                Text(value > 0 ? "Unmuted" : "Muted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            
            // Percentage Text
            if type != .mic && showsPercentage {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .frame(width: 35, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0: return "speaker.slash"
            case 0...0.33: return "speaker.wave.1"
            case 0.33...0.66: return "speaker.wave.2"
            default: return "speaker.wave.3"
        }
    }
    
    func updateSystemValue(_ newVal: CGFloat) {
        switch type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newVal))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newVal))
        default:
            break
        }
    }
}

#Preview {
    OpenNotchHUD(type: .constant(.volume), value: .constant(0.5), icon: .constant(""))
        .environmentObject(BoringViewModel())
        .padding()
        .background(Color.gray)
}
