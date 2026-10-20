import SwiftUI

/// Manual MDI basal bolus entry sheet; allows recording a long-acting insulin dose
/// directly from the Home screen or Treatments.
struct BasalBolusEntryView: View {
    @Binding var isPresented: Bool
    let lastBasal: (amount: Decimal, timestamp: Date)?
    let onSave: (Decimal, Date) -> Void

    @State private var amount: Decimal = 0
    @State private var date: Date = Date()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

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
                        Text(
                            String(
                                localized: "Last recorded: \(lastBasal.amount.formatted()) U at \(lastBasal.timestamp.formatted(date: .omitted, time: .shortened))",
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
                        onSave(amount, date)
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
