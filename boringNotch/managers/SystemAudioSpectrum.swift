//
//  SystemAudioSpectrum.swift
//  boringNotch
//
//  The real spectrum of what's playing, for the closed notch's equaliser. It taps the Mac's audio output with a
//  Core Audio process tap (macOS 14.2 and later), and splits each block of samples into four frequency bands
//  with an FFT. Nothing is recorded or kept; only the four band levels leave the audio thread.
//
//  macOS asks once for permission to capture system audio. Without it, or on older macOS, `isLive` stays false and
//  the equaliser falls back to its animation.
//

import Accelerate
import AudioToolbox
import Combine
import CoreAudio
import Foundation

@MainActor
final class SystemAudioSpectrum: ObservableObject {
    static let shared = SystemAudioSpectrum()

    static let bandCount = 4

    /// Band levels from 0 to 1, low to high frequencies.
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: SystemAudioSpectrum.bandCount)
    /// Whether the levels come from real audio.
    @Published private(set) var isLive = false

    private var capture: AnyObject?
    private var wanted = 0

    /// Starts capturing while at least one equaliser wants it.
    func retain() {
        wanted += 1
        guard wanted == 1 else { return }
        if #available(macOS 14.2, *) {
            let capture = SystemAudioCapture { [weak self] bands in
                Task { @MainActor in self?.levels = bands }
            }
            if capture.start() {
                self.capture = capture
                isLive = true
            }
        }
    }

    func release() {
        wanted = max(0, wanted - 1)
        guard wanted == 0 else { return }
        if #available(macOS 14.2, *) {
            (capture as? SystemAudioCapture)?.stop()
        }
        capture = nil
        isLive = false
        levels = Array(repeating: 0, count: Self.bandCount)
    }
}

@available(macOS 14.2, *)
private final class SystemAudioCapture {
    private let onBands: ([Float]) -> Void
    private let queue = DispatchQueue(label: "boringNotch.audioSpectrum", qos: .userInteractive)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    // FFT state, only touched on `queue`
    private static let fftSize = 1024
    private let fftSetup: vDSP.FFT<DSPSplitComplex>?
    private var window = [Float](repeating: 0, count: SystemAudioCapture.fftSize)
    private var samples = [Float]()
    private var smoothed = [Float](repeating: 0, count: SystemAudioSpectrum.bandCount)
    private var peak: Float = 1e-3
    private var sampleRate: Double = 48_000
    private var lastPublish = Date.distantPast

    init(onBands: @escaping ([Float]) -> Void) {
        self.onBands = onBands
        fftSetup = vDSP.FFT(log2n: vDSP_Length(log2(Double(Self.fftSize))), radix: .radix2, ofType: DSPSplitComplex.self)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        samples.reserveCapacity(Self.fftSize * 2)
    }

    deinit {
        stop()
    }

    /// Returns false if the tap couldn't be created (no permission, for example).
    func start() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return false }

        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Boring Notch Spectrum",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        // Clocked by the current output device
        if let outputUID = defaultOutputDeviceUID() {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
        }
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            stop()
            return false
        }

        if let rate = nominalSampleRate(of: aggregateID) {
            sampleRate = rate
        }

        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.consume(input)
        }
        guard status == noErr, AudioDeviceStart(aggregateID, ioProcID) == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
    }

    private func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return nil }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private func nominalSampleRate(of device: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        return rate
    }

    /// Mixes the block down to mono and runs the FFT whenever enough samples have built up.
    private func consume(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = max(1, Int(first.mNumberChannels))
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        let pointer = data.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += pointer[frame * channels + channel]
            }
            samples.append(sum / Float(channels))
        }

        while samples.count >= Self.fftSize {
            analyse(Array(samples.prefix(Self.fftSize)))
            samples.removeFirst(Self.fftSize / 2)
        }
    }

    private func analyse(_ block: [Float]) {
        guard let fftSetup else { return }
        let half = Self.fftSize / 2
        var windowed = [Float](repeating: 0, count: Self.fftSize)
        vDSP.multiply(block, window, result: &windowed)

        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { windowedPointer in
                    windowedPointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                let input = split
                fftSetup.forward(input: input, output: &split)
                vDSP.absolute(split, result: &magnitudes)
            }
        }

        // Bass, low mids, high mids, treble
        let edges: [Double] = [40, 250, 1_000, 4_000, 14_000]
        let binWidth = sampleRate / Double(Self.fftSize)
        var bands = [Float](repeating: 0, count: SystemAudioSpectrum.bandCount)
        for band in 0..<bands.count {
            let low = max(1, Int(edges[band] / binWidth))
            let high = min(half - 1, max(low + 1, Int(edges[band + 1] / binWidth)))
            bands[band] = vDSP.mean(magnitudes[low..<high])
        }

        // Follow the loudest recent level so quiet and loud songs both fill the bars
        let loudest = bands.max() ?? 0
        peak = max(loudest, peak * 0.995, 1e-3)
        for band in 0..<bands.count {
            let level = min(1, sqrt(bands[band] / peak))
            // Rise fast, fall slowly
            smoothed[band] = level > smoothed[band] ? level : smoothed[band] * 0.82 + level * 0.18
        }

        let now = Date()
        guard now.timeIntervalSince(lastPublish) >= 1.0 / 30 else { return }
        lastPublish = now
        onBands(smoothed)
    }
}
