import Foundation
import LoopKit
import LoopKitUI
import MockKit
import SwiftDate
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var setupPump = false
        private(set) var setupPumpEntry: PumpCatalogEntry?
        @Published var pumpState: PumpDisplayState?
        private(set) var initialSettings: PumpInitialSettings = .default
        @Injected() var bluetoothManager: BluetoothStateManager!
        @Injected() var broadcaster: Broadcaster!

        var isSimulator: Bool {
            (provider.apsManager.pumpManager as? MockPumpManager) != nil
        }

        @Published var heartbeatMode: HeartbeatMode = .none
        @Published var heartbeatDeviceName: String? = nil
        @Published var heartbeatDeviceAddress: String? = nil
        @Published var heartbeatDeviceType: String? = nil

        func selectHeartbeatDevice(_ device: DiscoveredHeartbeatDevice) {
            heartbeatDeviceAddress = device.id
            heartbeatDeviceName = device.name
            heartbeatDeviceType = device.type.rawValue
            heartbeatMode = .bluetooth
        }

        func disconnectHeartbeatDevice() {
            heartbeatDeviceAddress = nil
            heartbeatDeviceName = nil
            heartbeatDeviceType = nil
            heartbeatMode = .none
        }

        override func subscribe() {
            subscribeSetting(\.heartbeatMode, on: $heartbeatMode) { [weak self] in self?.heartbeatMode = $0 }
            subscribeSetting(\.heartbeatDeviceName, on: $heartbeatDeviceName) { [weak self] in self?.heartbeatDeviceName = $0 }
            subscribeSetting(\.heartbeatDeviceAddress, on: $heartbeatDeviceAddress) { [weak self] in self?.heartbeatDeviceAddress = $0 }
            subscribeSetting(\.heartbeatDeviceType, on: $heartbeatDeviceType) { [weak self] in self?.heartbeatDeviceType = $0 }

            broadcaster.register(SettingsObserver.self, observer: self)

            provider.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .assign(to: \.pumpState, on: self)
                .store(in: &lifetime)
            Task {
                let basalSchedule = BasalRateSchedule(
                    dailyItems: await provider.getBasalProfile().map {
                        RepeatingScheduleValue(startTime: $0.minutes.minutes.timeInterval, value: Double($0.rate))
                    }
                )

                let pumpSettings = provider.pumpSettings()

                await MainActor.run {
                    initialSettings = PumpInitialSettings(
                        maxBolusUnits: Double(pumpSettings.maxBolus),
                        maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                        basalSchedule: basalSchedule!
                    )
                }
            }
        }

        func addPump(_ entry: PumpCatalogEntry) {
            setupPumpEntry = entry
            setupPump = true
        }
    }
}

extension PumpConfig.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}

extension PumpConfig.StateModel: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        provider.setPumpManager(pumpManager)
        if let insulinType = pumpManager.status.insulinType {
            settingsManager.updateInsulinCurve(insulinType)
        }
    }

    func pumpManagerOnboarding(didOnboardPumpManager _: PumpManagerUI) {
        // nothing to do
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {
        // TODO:
    }
}

extension PumpConfig.StateModel: SettingsObserver {
    func settingsDidChange(_ settings: TrioSettings) {
        if heartbeatMode != settings.heartbeatMode {
            heartbeatMode = settings.heartbeatMode
        }
        if heartbeatDeviceName != settings.heartbeatDeviceName {
            heartbeatDeviceName = settings.heartbeatDeviceName
        }
        if heartbeatDeviceAddress != settings.heartbeatDeviceAddress {
            heartbeatDeviceAddress = settings.heartbeatDeviceAddress
        }
        if heartbeatDeviceType != settings.heartbeatDeviceType {
            heartbeatDeviceType = settings.heartbeatDeviceType
        }
    }
}

