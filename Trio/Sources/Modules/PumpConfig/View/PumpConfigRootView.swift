import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        let bluetoothManager: BluetoothStateManager
        @StateObject var state = StateModel()
        @ObservedObject var heartbeatManager = HeartBeatManager.shared
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var showPumpSelection: Bool = false
        @State private var pendingPump: PumpCatalogEntry?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("Pump Integration to Trio"),
                    content: {
                        if bluetoothManager.bluetoothAuthorization != .authorized {
                            HStack {
                                Spacer()
                                BluetoothRequiredView()
                                Spacer()
                            }
                        } else if let pumpState = state.pumpState {
                            Button {
                                state.setupPump = true
                            } label: {
                                HStack {
                                    Image(uiImage: pumpState.image ?? UIImage())
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 100)
                                    Text(pumpState.name)
                                }
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                                .font(.title2)
                            }.padding()
                        } else {
                            VStack {
                                Button {
                                    showPumpSelection.toggle()
                                } label: {
                                    Text("Add Pump")
                                        .font(.title3) }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)

                                HStack(alignment: .center) {
                                    Text(
                                        "Pair your insulin pump with Trio. See hint for compatible devices."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            shouldDisplayHint.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                                    .accessibilityLabel(Text("More information"))
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                }.padding(.top)
                            }.padding(.vertical)
                        }
                    }
                ).listRowBackground(Color.chart)

                if state.isSimulator {
                    virtualPumpHeartbeatSection
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .onDisappear {
                heartbeatManager.stopScanning()
            }
            .navigationBarTitleDisplayMode(.automatic)
            .navigationTitle("Insulin Pump")
            .sheet(isPresented: $state.setupPump) {
                if let pumpManager = state.provider?.apsManager.pumpManager {
                    PumpSettingsView(
                        pumpManager: pumpManager,
                        bluetoothManager: state.provider?.apsManager.bluetoothManager ?? bluetoothManager,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                } else if let pumpEntry = state.setupPumpEntry {
                    PumpSetupView(
                        pumpEntry: pumpEntry,
                        pumpInitialSettings: state.initialSettings,
                        bluetoothManager: state.provider?.apsManager.bluetoothManager ?? bluetoothManager,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                }
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: "Pump Pairing to Trio",
                    hintText: AnyView(
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Current Pump Models Supported:"
                            )
                            VStack(alignment: .leading) {
                                ForEach(DeviceCatalog.pumps) { pump in
                                    Text("• \(pump.hintLine)")
                                }
                            }
                            Text(
                                "Note: If using a pump simulator, you will not have continuous readings from the CGM in Trio. Using a pump simulator is only advisable for becoming familiar with the app user interface. It will not give you insight on how the algorithm will respond."
                            )
                        }
                    ),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            // Selection is applied in onDismiss so the setup sheet is presented only once the picker is gone.
            .sheet(isPresented: $showPumpSelection, onDismiss: {
                if let entry = pendingPump {
                    pendingPump = nil
                    state.addPump(entry)
                }
            }) {
                DevicePickerView(
                    title: String(localized: "Add Pump", comment: "The title of the pump chooser in settings"),
                    entries: DeviceCatalog.pumps
                ) { entry in
                    pendingPump = entry
                    showPumpSelection = false
                }
            }
        }

        private var virtualPumpHeartbeatSection: some View {
            Section(
                header: Text("Virtual Pump Heartbeat"),
                footer: Text(heartbeatFooterText)
            ) {
                Picker("Heartbeat Mode", selection: $state.heartbeatMode) {
                    ForEach(HeartbeatMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if state.heartbeatMode == .silentAudio {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.orange)
                        Text("Silent Audio Keep-Alive")
                        Spacer()
                        Text(heartbeatManager.connectionStatus)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let last = heartbeatManager.lastHeartbeatDate {
                        HStack {
                            Text("Last Heartbeat")
                            Spacer()
                            Text(last, style: .time)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if state.heartbeatMode == .bluetooth {
                    if let name = state.heartbeatDeviceName, !name.isEmpty {
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text(name)
                                    .font(.headline)
                                if let addr = state.heartbeatDeviceAddress {
                                    Text(addr)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button("Forget") {
                                state.disconnectHeartbeatDevice()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }

                        HStack {
                            Text("Status")
                            Spacer()
                            Text(heartbeatManager.connectionStatus)
                                .foregroundColor(.secondary)
                        }

                        if let last = heartbeatManager.lastHeartbeatDate {
                            HStack {
                                Text("Last Heartbeat")
                                Spacer()
                                Text(last, style: .time)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Nearby BLE Devices")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            if heartbeatManager.isScanning {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Button("Stop") {
                                    heartbeatManager.stopScanning()
                                }
                                .font(.caption)
                            } else {
                                Button("Scan") {
                                    heartbeatManager.startScanning()
                                }
                                .font(.caption)
                            }
                        }

                        if heartbeatManager.discoveredDevices.isEmpty {
                            if heartbeatManager.isScanning {
                                Text("Scanning for nearby Omnipod DASH, RileyLink, Dexcom...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Tap Scan to discover nearby Bluetooth devices.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            ForEach(heartbeatManager.discoveredDevices) { device in
                                Button {
                                    state.selectHeartbeatDevice(device)
                                    heartbeatManager.stopScanning()
                                } label: {
                                    HStack {
                                        Image(systemName: deviceIconName(device.type))
                                            .foregroundColor(.accentColor)
                                        VStack(alignment: .leading) {
                                            Text(device.name)
                                                .foregroundColor(.primary)
                                            Text("\(device.type.displayName) • RSSI: \(device.rssi) dBm")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if device.id == state.heartbeatDeviceAddress {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.chart)
        }

        private var heartbeatFooterText: String {
            switch state.heartbeatMode {
            case .none:
                return "Without a heartbeat, iOS will suspend Trio in the background when using a Virtual Pump."
            case .bluetooth:
                return "Bluetooth Heartbeat listens to periodic transmissions from DASH pods, RileyLink, or Dexcom to awaken Trio in the background."
            case .silentAudio:
                return "Silent Audio plays inaudible sound in background to keep Trio active without needing a Bluetooth device. Consumes more battery and may pause during phone calls or timer alarms."
            }
        }

        private func deviceIconName(_ type: HeartbeatDeviceType) -> String {
            switch type {
            case .omnipodDash: return "cross.case.fill"
            case .rileyLink: return "antenna.radiowaves.left.and.right"
            case .dexcom: return "sensor.fill"
            case .generic: return "wave.3.right"
            }
        }
    }
}
