import SwiftUI
import UIKit

/// Common long-acting (basal) insulins recognized by external drug and activity calculators
/// (e.g., GLA = Lantus/Glargine, DET = Levemir/Detemir, TOU = Toujeo, DEG = Tresiba/Degludec, NPH = Protaphane/NPH).
enum BasalDrug: String, CaseIterable, Identifiable, Codable {
    case lantus = "Lantus"
    case glargine = "Glargine"
    case tresiba = "Tresiba"
    case degludec = "Degludec"
    case toujeo = "Toujeo"
    case levemir = "Levemir"
    case detemir = "Detemir"
    case nph = "NPH"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lantus: return "Lantus (Glargine U-100)"
        case .glargine: return "Glargine"
        case .tresiba: return "Tresiba (Degludec)"
        case .degludec: return "Degludec"
        case .toujeo: return "Toujeo (Glargine U-300)"
        case .levemir: return "Levemir (Detemir)"
        case .detemir: return "Detemir"
        case .nph: return "NPH (Protaphane)"
        }
    }
}

/// Manual MDI basal bolus entry sheet; allows recording a long-acting insulin dose
/// directly from the Home screen or Treatments.
struct BasalBolusEntryView: View {
    @Binding var isPresented: Bool
    let lastBasal: (amount: Decimal, timestamp: Date, insulin: String?)?
    let onSave: (Decimal, Date, String) -> Void

    @AppStorage("selectedBasalInsulin") private var selectedBasalInsulin: String = BasalDrug.lantus.rawValue
    @State private var amount: Decimal = 0
    @State private var date: Date = Date()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    init(
        isPresented: Binding<Bool>,
        lastBasal: (amount: Decimal, timestamp: Date, insulin: String?)?,
        onSave: @escaping (Decimal, Date, String) -> Void
    ) {
        self._isPresented = isPresented
        self.lastBasal = lastBasal
        self.onSave = onSave
    }

    init(
        isPresented: Binding<Bool>,
        lastBasal: (amount: Decimal, timestamp: Date)?,
        onSave: @escaping (Decimal, Date) -> Void
    ) {
        self._isPresented = isPresented
        self.lastBasal = lastBasal.map { ($0.amount, $0.timestamp, nil) }
        self.onSave = { amount, date, _ in onSave(amount, date) }
    }

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.allowsFloats = true
        return formatter
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker(
                        selection: $selectedBasalInsulin,
                        label: Text(String(localized: "Insulin", comment: "Label for basal insulin type picker"))
                    ) {
                        ForEach(BasalDrug.allCases) { drug in
                            Text(drug.displayName).tag(drug.rawValue)
                        }
                    }

                    HStack {
                        Text(String(localized: "Basal Dose", comment: "Label for basal insulin amount"))
                        TextFieldWithToolBar(
                            text: $amount,
                            placeholder: "0.0",
                            keyboardType: .decimalPad,
                            numberFormatter: formatter,
                            initialFocus: true,
                            unitsText: String(localized: "U", comment: "Units of insulin")
                        )
                    }

                    DatePicker(
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    ) {
                        Text(String(localized: "Time", comment: "Label for date/time of basal bolus"))
                    }
                } header: {
                    Text(String(localized: "Basal Injection", comment: "Section header for basal injection"))
                } footer: {
                    if let lastBasal {
                        let insulinInfo = lastBasal.insulin != nil ? " (\(lastBasal.insulin!))" : ""
                        Text(
                            String(
                                localized: "Last recorded: \(lastBasal.amount.formatted()) U\(insulinInfo) at \(lastBasal.timestamp.formatted(date: .omitted, time: .shortened))",
                                comment: "Footer showing last recorded basal bolus"
                            )
                        )
                    }
                }
                .listRowBackground(Color.chart)

                Section {
                    Button {
                        guard amount > 0 else { return }
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        onSave(amount, date, selectedBasalInsulin)
                        isPresented = false
                    } label: {
                        Text(String(localized: "Save Basal Bolus", comment: "Button label to save basal bolus"))
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(amount <= 0 || amount > 150)
                }
                .listRowBackground(
                    amount <= 0 || amount > 150 ? Color(.systemGray4) : Color.insulin
                )
                .tint(.white)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(String(localized: "MDI Basal", comment: "Navigation title for basal entry sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel", comment: "Cancel button")) {
                        isPresented = false
                    }
                }
            }
        }
    }
}
