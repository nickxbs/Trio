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

        var isSimulator: Bool {
            (provider.apsManager.pumpManager as? MockPumpManager) != nil
        }

        var heartbeatMode: HeartbeatMode {
            get { settingsManager.settings.heartbeatMode }
            set {
                var s = settingsManager.settings
                s.heartbeatMode = newValue
                settingsManager.settings = s
            }
        }

        var heartbeatDeviceName: String? {
            settingsManager.settings.heartbeatDeviceName
        }

        var heartbeatDeviceAddress: String? {
            settingsManager.settings.heartbeatDeviceAddress
        }

        func selectHeartbeatDevice(_ device: DiscoveredHeartbeatDevice) {
            var s = settingsManager.settings
            s.heartbeatDeviceAddress = device.id
            s.heartbeatDeviceName = device.name
            s.heartbeatDeviceType = device.type.rawValue
            s.heartbeatMode = .bluetooth
            settingsManager.settings = s
        }

        func disconnectHeartbeatDevice() {
            var s = settingsManager.settings
            s.heartbeatDeviceAddress = nil
            s.heartbeatDeviceName = nil
            s.heartbeatDeviceType = nil
            s.heartbeatMode = .none
            settingsManager.settings = s
        }

        override func subscribe() {
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
