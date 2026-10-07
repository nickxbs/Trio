import AVFoundation
import Combine
import CoreBluetooth
import Foundation

// MARK: - Heartbeat Device Types

public enum HeartbeatDeviceType: String, JSON, CaseIterable, Identifiable {
    public var id: String { rawValue }

    case omnipodDash
    case rileyLink
    case dexcom
    case generic

    public var displayName: String {
        switch self {
        case .omnipodDash:
            return "Omnipod DASH"
        case .rileyLink:
            return "RileyLink / OrangeLink"
        case .dexcom:
            return "Dexcom G6 / G7"
        case .generic:
            return "Generic BLE"
        }
    }

    public var serviceUUID: String {
        switch self {
        case .omnipodDash:
            return "1A7E4024-E3ED-4464-8B7E-751E03D0DC5F"
        case .rileyLink:
            return "0235733B-99C5-4197-B856-69219C2A3845"
        case .dexcom:
            return "F8083532-849E-531C-C594-30F1F86A4EA5"
        case .generic:
            return ""
        }
    }

    public var receiveCharacteristicUUID: String {
        switch self {
        case .omnipodDash:
            return "1A7E2442-E3ED-4464-8B7E-751E03D0DC5F"
        case .rileyLink:
            return "6E6C7910-B89E-43A5-78AF-50C5E2B86F7E"
        case .dexcom:
            return "F8083535-849E-531C-C594-30F1F86A4EA5"
        case .generic:
            return ""
        }
    }

    public static func detectType(name: String?, advertisedServices: [CBUUID]?) -> HeartbeatDeviceType {
        let nameLower = (name ?? "").lowercased()
        let serviceStrings = (advertisedServices ?? []).map { $0.uuidString.uppercased() }

        if serviceStrings.contains("1A7E4024-E3ED-4464-8B7E-751E03D0DC5F") ||
            serviceStrings.contains("00004024-0000-1000-8000-00805F9B34FB") ||
            nameLower.contains("omnipod") || nameLower.contains("dash")
        {
            return .omnipodDash
        }

        if serviceStrings.contains("0235733B-99C5-4197-B856-69219C2A3845") ||
            nameLower.contains("rileylink") || nameLower.contains("orangelink") || nameLower.contains("emmalink")
        {
            return .rileyLink
        }

        if serviceStrings.contains("F8083532-849E-531C-C594-30F1F86A4EA5") ||
            serviceStrings.contains("FEBC") ||
            nameLower.contains("dexcom")
        {
            return .dexcom
        }

        return .generic
    }
}

// MARK: - Discovered Heartbeat Device

public struct DiscoveredHeartbeatDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public var rssi: Int
    public let type: HeartbeatDeviceType
    public var lastSeen: Date

    public init(id: String, name: String, rssi: Int, type: HeartbeatDeviceType, lastSeen: Date) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.type = type
        self.lastSeen = lastSeen
    }
}

// MARK: - Silent Audio Player (Background Keep-Alive)

final class SilentAudioPlayer: NSObject {
    static let shared = SilentAudioPlayer()

    private var player: AVAudioPlayer?
    private var keepAliveTimer: Timer?
    private var onTick: (() -> Void)?
    private(set) var isPlaying: Bool = false

    override private init() {
        super.init()
        setupNotifications()
    }

    private func setupNotifications() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    func start(onTick: @escaping () -> Void) {
        self.onTick = onTick
        stop()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let silentData = Self.createSilentWAVData()
            player = try AVAudioPlayer(data: silentData)
            player?.numberOfLoops = -1
            player?.volume = 0.01 // inaudible
            player?.prepareToPlay()
            player?.play()
            isPlaying = true

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.keepAliveTimer?.invalidate()
                // Periodic tick to fire background glucose fetch and loop evaluation
                self.keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                    self?.onTick?()
                }
            }
            debug(.deviceManager, "SilentAudioPlayer: started successfully")
        } catch {
            debug(.deviceManager, "SilentAudioPlayer: failed to start: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        debug(.deviceManager, "SilentAudioPlayer: stopped")
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        if type == .ended, isPlaying {
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        if isPlaying, reason == .oldDeviceUnavailable {
            // E.g. AirPods/Bluetooth disconnected: iOS pauses audio by default, resume it immediately.
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
        }
    }

    @objc private func handleMediaReset() {
        if isPlaying, let onTick = onTick {
            start(onTick: onTick)
        }
    }

    /// Generates a valid 2-second in-memory silent 16-bit PCM WAV file
    private static func createSilentWAVData() -> Data {
        let sampleRate: UInt32 = 8000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let durationSeconds: UInt32 = 2
        let numSamples = sampleRate * durationSeconds
        let dataSize = numSamples * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let chunkSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = numChannels * (bitsPerSample / 8)
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        data.append(Data(count: Int(dataSize))) // 16-bit zeros = digital silence
        return data
    }
}

// MARK: - BLE Heartbeat Scanner

final class BLEHeartbeatScanner: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager?
    private var onDevicesUpdated: (([DiscoveredHeartbeatDevice]) -> Void)?
    private var devicesMap: [String: DiscoveredHeartbeatDevice] = [:]
    private(set) var isScanning: Bool = false

    func startScanning(onDevicesUpdated: @escaping ([DiscoveredHeartbeatDevice]) -> Void) {
        self.onDevicesUpdated = onDevicesUpdated
        devicesMap.removeAll()
        isScanning = true

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        } else if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }

        // Safety timeout to preserve battery
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
            guard let self = self, self.isScanning else { return }
            self.stopScanning()
        }
    }

    func stopScanning() {
        isScanning = false
        centralManager?.stopScan()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, isScanning {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ??
            (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ??
            "Unknown"

        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])

        let type = HeartbeatDeviceType.detectType(name: name, advertisedServices: services)
        let id = peripheral.identifier.uuidString

        let device = DiscoveredHeartbeatDevice(
            id: id,
            name: name,
            rssi: RSSI.intValue,
            type: type,
            lastSeen: Date()
        )

        devicesMap[id] = device
        let sorted = devicesMap.values.sorted { $0.rssi > $1.rssi }
        onDevicesUpdated?(Array(sorted))
    }
}

// MARK: - HeartBeatManager

public final class HeartBeatManager: NSObject, ObservableObject {
    private let keyForcgmTransmitterDeviceAddress = "cgmTransmitterDeviceAddress"
    private let keyForcgmTransmitter_CBUUID_Service = "cgmTransmitter_CBUUID_Service"
    private let keycgmTransmitter_CBUUID_Receive = "cgmTransmitter_CBUUID_Receive"

    public static let shared = HeartBeatManager()

    @Published public private(set) var lastHeartbeatDate: Date? = nil
    @Published public private(set) var connectionStatus: String = "Disconnected"
    @Published public private(set) var activeDeviceName: String? = nil
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var discoveredDevices: [DiscoveredHeartbeatDevice] = []

    private var bluetoothTransmitter: BluetoothTransmitter?
    private var initialSetupDone = false
    private let scanner = BLEHeartbeatScanner()
    private var configuredMode: HeartbeatMode?
    private var configuredAddress: String?

    public var onHeartbeat: (() -> Void)?

    public var isHeartbeatActive: Bool {
        SilentAudioPlayer.shared.isPlaying || bluetoothTransmitter != nil
    }

    override private init() {
        super.init()
    }

    // MARK: - Setup & Configuration

    func applySettings(settings: TrioSettings) {
        let newMode = settings.heartbeatMode
        let newAddress = settings.heartbeatDeviceAddress

        if configuredMode == newMode, configuredAddress == newAddress {
            return
        }

        configuredMode = newMode
        configuredAddress = newAddress

        switch newMode {
        case .none:
            stop()

        case .silentAudio:
            stopBluetooth()
            activeDeviceName = "Silent Audio"
            connectionStatus = "Active (Audio loop)"
            SilentAudioPlayer.shared.start { [weak self] in
                self?.handleHeartbeatTrigger()
            }

        case .bluetooth:
            SilentAudioPlayer.shared.stop()
            guard let address = newAddress, !address.isEmpty else {
                stop()
                return
            }
            let deviceType = HeartbeatDeviceType(rawValue: settings.heartbeatDeviceType ?? "") ?? .generic
            activeDeviceName = settings.heartbeatDeviceName ?? deviceType.displayName
            connectionStatus = "Connecting..."

            bluetoothTransmitter = BluetoothTransmitter(
                deviceAddress: address,
                servicesCBUUID: deviceType.serviceUUID,
                CBUUID_Receive: deviceType.receiveCharacteristicUUID,
                heartbeat: { [weak self] in
                    self?.handleHeartbeatTrigger()
                }
            )
        }
    }

    private func handleHeartbeatTrigger() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastHeartbeatDate = Date()
            self.connectionStatus = "Heartbeat received"
            self.onHeartbeat?()
        }
    }

    public func stop() {
        configuredMode = .none
        configuredAddress = nil
        stopBluetooth()
        SilentAudioPlayer.shared.stop()
        connectionStatus = "Disconnected"
        activeDeviceName = nil
    }

    private func stopBluetooth() {
        bluetoothTransmitter?.disconnect()
        bluetoothTransmitter = nil
    }

    // MARK: - Scanning

    public func startScanning() {
        isScanning = true
        scanner.startScanning { [weak self] devices in
            DispatchQueue.main.async {
                self?.discoveredDevices = devices
            }
        }
    }

    public func stopScanning() {
        isScanning = false
        scanner.stopScanning()
    }

    // MARK: - AppGroup / xDrip4iOS Legacy Compatibility

    func checkCGMBluetoothTransmitter(sharedUserDefaults: UserDefaults, heartbeat: DispatchTimer?) {
        if !initialSetupDone {
            initialSetupDone = true
            UserDefaults.standard.cgmTransmitterDeviceAddress = nil
        }

        if UserDefaults.standard.cgmTransmitterDeviceAddress != sharedUserDefaults
            .string(forKey: keyForcgmTransmitterDeviceAddress)
        {
            UserDefaults.standard.cgmTransmitterDeviceAddress = sharedUserDefaults
                .string(forKey: keyForcgmTransmitterDeviceAddress)

            bluetoothTransmitter = setupBluetoothTransmitter(sharedData: sharedUserDefaults, heartbeat: heartbeat)
        }
    }

    private func setupBluetoothTransmitter(sharedData: UserDefaults, heartbeat: DispatchTimer?) -> BluetoothTransmitter? {
        if let cgmTransmitterDeviceAddress = sharedData.string(forKey: keyForcgmTransmitterDeviceAddress) {
            if let cgmTransmitter_CBUUID_Service = sharedData.string(forKey: keyForcgmTransmitter_CBUUID_Service),
               let cgmTransmitter_CBUUID_Receive = sharedData.string(forKey: keycgmTransmitter_CBUUID_Receive)
            {
                let newBluetoothTransmitter = BluetoothTransmitter(
                    deviceAddress: cgmTransmitterDeviceAddress,
                    servicesCBUUID: cgmTransmitter_CBUUID_Service,
                    CBUUID_Receive: cgmTransmitter_CBUUID_Receive,
                    heartbeat: { [weak self] in
                        if let heartbeatAvailable = heartbeat {
                            heartbeatAvailable.fire()
                        }
                        self?.handleHeartbeatTrigger()
                    }
                )
                return newBluetoothTransmitter
            }
        }
        return nil
    }
}
