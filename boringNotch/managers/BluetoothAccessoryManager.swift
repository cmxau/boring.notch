//
//  BluetoothAccessoryManager.swift
//  boringNotch
//
//  Watches for Bluetooth accessories connecting and works out which artwork to show for them.
//

import CoreBluetooth
import Defaults
import Foundation
import IOBluetooth
import os

enum AccessoryArtwork: Equatable {
    /// A looping clip bundled with the app, named without its `.mp4` extension, and the SF Symbol to use if
    /// the clip is missing.
    case video(String, fallbackSymbol: String = "airpods")
    /// An SF Symbol for accessories we don't have a clip for.
    case symbol(String)
}

struct ConnectedAccessory: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let artwork: AccessoryArtwork
}

/// AirPods models, keyed by their Bluetooth product ID.
enum AirPodsModel {
    case airPods1
    case airPods2
    case airPods3
    case airPods4
    case airPods4ANC
    case pro
    case pro2
    case pro2USBC
    case pro3
    case max
    case maxUSBC

    init?(productID: UInt16) {
        switch productID {
        case 0x2002: self = .airPods1
        case 0x200F: self = .airPods2
        case 0x2013: self = .airPods3
        case 0x2019: self = .airPods4
        case 0x201B: self = .airPods4ANC
        case 0x200E: self = .pro
        case 0x2014: self = .pro2
        case 0x2024: self = .pro2USBC
        case 0x2027: self = .pro3
        case 0x200A: self = .max
        case 0x201F: self = .maxUSBC
        default: return nil
        }
    }

    /// Best guess from the device name, for when the product ID isn't available.
    init?(name: String) {
        let name = name.lowercased()
        if name.contains("airpods max") {
            self = .max
        } else if name.contains("airpods pro") {
            self = .pro2
        } else if name.contains("airpods") {
            self = .airPods4
        } else {
            return nil
        }
    }

    var isMax: Bool {
        self == .max || self == .maxUSBC
    }

    /// Clip for every model except AirPods Max, whose clip depends on its colour.
    var video: String {
        switch self {
        // There's no clip for the first two generations, so they use the closest design
        case .airPods1, .airPods2, .airPods3: return "airpods-3"
        case .airPods4, .airPods4ANC: return "airpods-4"
        case .pro: return "airpods-pro"
        case .pro2, .pro2USBC: return "airpods-pro-2"
        case .pro3: return "airpods-pro-3"
        case .max, .maxUSBC: return "airpods-max-space-gray"
        }
    }

    /// AirPods Max clip for the colour byte in the AirPods' proximity pairing advertisement.
    func maxVideo(colorCode: UInt8?) -> String {
        if self == .max {
            switch colorCode {
            case 0x00: return "airpods-max-silver"
            case 0x02: return "airpods-max-red"
            case 0x03: return "airpods-max-sky-blue"
            case 0x0F: return "airpods-max-space-gray"
            case 0x11: return "airpods-max-green"
            default: return "airpods-max-space-gray"
            }
        }
        // Colour codes for the USB-C AirPods Max (midnight, starlight, blue, purple, orange) aren't known yet
        return "airpods-max-midnight"
    }

    static let knownMaxColorCodes: Set<UInt8> = [0x00, 0x02, 0x03, 0x0F, 0x11]
}

@MainActor
final class BluetoothAccessoryManager: NSObject {
    static let shared = BluetoothAccessoryManager()

    private let logger = Logger(subsystem: "com.theboringteam.boringnotch", category: "BluetoothAccessory")

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var connectedAddresses: Set<String> = []
    private var lastShown: [String: Date] = [:]
    private var startedAt: Date = .distantPast
    private var colorScanner: AirPodsColorScanner?
    private var enabledObserver: Task<Void, Never>?

    func start() {
        guard enabledObserver == nil else { return }
        enabledObserver = Task { [weak self] in
            for await enabled in Defaults.updates(.showAccessoryConnectedIndicator) {
                if enabled {
                    self?.startMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }
        }
    }

    private func startMonitoring() {
        guard connectNotification == nil else { return }
        startedAt = Date()

        // Remember what's already connected so only new connections are announced
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for device in paired where device.isConnected() {
            guard let address = device.addressString else { continue }
            connectedAddresses.insert(address)
            watchDisconnect(of: device, address: address)
        }

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceDidConnect(_:device:))
        )
    }

    private func stopMonitoring() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        connectedAddresses.removeAll()
    }

    @objc private func deviceDidConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }

        let wasConnected = connectedAddresses.contains(address)
        connectedAddresses.insert(address)
        watchDisconnect(of: device, address: address)

        // Registering replays connect notifications for devices that were already connected
        guard !wasConnected, Date().timeIntervalSince(startedAt) > 2 else { return }

        // Accessories sometimes drop and reconnect straight away; don't announce each blip
        if let last = lastShown[address], Date().timeIntervalSince(last) < 10 { return }
        lastShown[address] = Date()

        Task { await self.announce(device, address: address) }
    }

    @objc private func deviceDidDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        connectedAddresses.remove(address)
        disconnectNotifications.removeValue(forKey: address)?.unregister()
    }

    private func watchDisconnect(of device: IOBluetoothDevice, address: String) {
        guard disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDidDisconnect(_:device:))
        )
    }

    private func announce(_ device: IOBluetoothDevice, address: String) async {
        let name = device.name ?? "Accessory"
        let artwork = await artwork(for: device, address: address, name: name)
        BoringViewCoordinator.shared.showAccessoryConnected(ConnectedAccessory(name: name, artwork: artwork))
    }

    private func artwork(for device: IOBluetoothDevice, address: String, name: String) async -> AccessoryArtwork {
        let info = await productInfo(of: device)

        if Self.isDualSense(info: info, name: name) {
            return .video("ps5-controller", fallbackSymbol: "gamecontroller.fill")
        }

        let model = info.flatMap { Self.isApple(vendorID: $0.vendor) ? AirPodsModel(productID: $0.product) : nil }
            ?? AirPodsModel(name: name)

        guard let model else {
            return .symbol(Self.symbol(for: device))
        }
        guard model.isMax else {
            return .video(model.video)
        }

        let productID = info?.product ?? 0x200A
        var colorCodes = Defaults[.airPodsMaxColorCodes]
        if let cached = colorCodes[address] {
            // Refresh in the background in case it's a different headset with the same address
            Task {
                if let code = await self.scanColor(productID: productID, timeout: 8) {
                    var codes = Defaults[.airPodsMaxColorCodes]
                    codes[address] = Int(code)
                    Defaults[.airPodsMaxColorCodes] = codes
                }
            }
            return .video(model.maxVideo(colorCode: UInt8(truncatingIfNeeded: cached)))
        }

        let code = await scanColor(productID: productID, timeout: 2.5)
        if let code {
            colorCodes[address] = Int(code)
            Defaults[.airPodsMaxColorCodes] = colorCodes
            if model == .max && !AirPodsModel.knownMaxColorCodes.contains(code) {
                logger.notice("Unknown AirPods Max colour code 0x\(String(format: "%02X", code), privacy: .public)")
            }
        }
        if model == .maxUSBC, let code {
            logger.notice("USB-C AirPods Max colour code 0x\(String(format: "%02X", code), privacy: .public)")
        }
        return .video(model.maxVideo(colorCode: code))
    }

    private func scanColor(productID: UInt16, timeout: TimeInterval) async -> UInt8? {
        guard colorScanner == nil else { return nil }
        let scanner = AirPodsColorScanner()
        colorScanner = scanner
        defer { colorScanner = nil }
        return await scanner.colorCode(productID: productID, timeout: timeout)
    }

    // MARK: - Device details

    /// PS5 DualSense and DualSense Edge controllers.
    private static func isDualSense(info: (vendor: UInt16, product: UInt16)?, name: String) -> Bool {
        if let info, info.vendor == 0x054C {
            return info.product == 0x0CE6 || info.product == 0x0DF2
        }
        return name.lowercased().contains("dualsense")
    }

    private static func isApple(vendorID: UInt16) -> Bool {
        // Apple's Bluetooth SIG and USB vendor IDs
        vendorID == 0x004C || vendorID == 0x05AC
    }

    /// Vendor and product ID from the device's PnP Information (Device ID) SDP record.
    private func productInfo(of device: IOBluetoothDevice) async -> (vendor: UInt16, product: UInt16)? {
        // The record is usually cached from pairing; if not, ask the device and give it a moment
        for attempt in 0..<6 {
            if let info = Self.cachedProductInfo(of: device) {
                return info
            }
            if attempt == 0 {
                device.performSDPQuery(nil)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    private static func cachedProductInfo(of device: IOBluetoothDevice) -> (vendor: UInt16, product: UInt16)? {
        guard let pnpInformation = IOBluetoothSDPUUID(uuid16: BluetoothSDPUUID16(0x1200)),
              let record = device.getServiceRecord(for: pnpInformation),
              let vendor = record.getAttributeDataElement(0x0201)?.getNumberValue(),
              let product = record.getAttributeDataElement(0x0202)?.getNumberValue()
        else { return nil }
        return (vendor.uint16Value, product.uint16Value)
    }

    private static func symbol(for device: IOBluetoothDevice) -> String {
        let minor = device.deviceClassMinor
        switch device.deviceClassMajor {
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio):
            switch minor {
            case 0x05, 0x0A: return "hifispeaker.fill"
            case 0x08: return "car.fill"
            default: return "headphones"
            }
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral):
            if minor & 0x0F == 0x01 || minor & 0x0F == 0x02 { return "gamecontroller.fill" }
            switch minor & 0x30 {
            case 0x10, 0x30: return "keyboard.fill"
            case 0x20: return "computermouse.fill"
            default: return "dot.radiowaves.left.and.right"
            }
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone):
            return "iphone"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorComputer):
            return "laptopcomputer"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}

/// Reads the colour byte from the proximity pairing advertisement AirPods broadcast over BLE.
private final class AirPodsColorScanner: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private var continuation: CheckedContinuation<UInt8?, Never>?
    private var productID: UInt16 = 0

    func colorCode(productID: UInt16, timeout: TimeInterval) async -> UInt8? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.productID = productID
            central = CBCentralManager(delegate: self, queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(nil)
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        case .unauthorized, .unsupported, .poweredOff:
            finish(nil)
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Apple company ID (0x004C), message type 0x07, then prefix, model (little endian), status,
        // battery, charging and case battery, lid counter, colour
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.count >= 12
        else { return }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x4C, bytes[1] == 0x00, bytes[2] == 0x07 else { return }

        let model = UInt16(bytes[6]) << 8 | UInt16(bytes[5])
        guard model == productID else { return }
        finish(bytes[11])
    }

    private func finish(_ code: UInt8?) {
        guard let continuation else { return }
        self.continuation = nil
        central?.stopScan()
        central = nil
        continuation.resume(returning: code)
    }
}
