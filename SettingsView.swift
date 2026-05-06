// SettingsView.swift
// ElevenLabsDashboard
//
// Configure: accounts, payout rate, polling interval, lookback windows.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var newAccountName = ""
    @State private var newAccountKey = ""
    @State private var showNewAccountKey = false
    @State private var payoutPasteText = ""
    @State private var payoutImportMessage = ""

    private let pollingOptions: [(label: String, minutes: Double)] = [
        ("5 minutes", 5),
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("6 hours", 360)
    ]

    var body: some View {
        Form {
            Section("ElevenLabs Accounts") {
                if viewModel.accounts.isEmpty {
                    Text("No accounts configured yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.accounts) { account in
                        AccountRow(account: account)
                            .environmentObject(viewModel)
                    }
                }

                if viewModel.accounts.count < viewModel.maxAccounts {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add account")
                            .font(.subheadline.bold())

                        TextField("Account name", text: $newAccountName)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            if showNewAccountKey {
                                TextField("xi-api-key", text: $newAccountKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("xi-api-key", text: $newAccountKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button {
                                showNewAccountKey.toggle()
                            } label: {
                                Image(systemName: showNewAccountKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        Button("Add Account") {
                            let created = viewModel.addAccount(name: newAccountName, apiKey: newAccountKey)
                            if created {
                                newAccountName = ""
                                newAccountKey = ""
                            } else {
                                viewModel.errorMessage = "Could not add account. Check inputs and max account limit (5)."
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newAccountKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 8)
                } else {
                    Text("Maximum of 5 accounts reached.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("API keys are stored securely in macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Payout Rate") {
                HStack {
                    Text("Global default rate per 1,000 characters")
                    Spacer()
                    HStack(spacing: 4) {
                        Text("$")
                        TextField("0.008010", value: $viewModel.ratePerThousand, format: .number.precision(.fractionLength(6)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }
                }

                Text("Used for all voices unless a voice-specific custom rate override is entered below.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Real Revenue Allocation") {
                DatePicker("Window start (payout start)", selection: $viewModel.lastPayoutDate, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Window end (payout end/present)", selection: $viewModel.payoutWindowEndDate, displayedComponents: [.date, .hourAndMinute])

                HStack {
                    Text("Total payouts since last payout")
                    Spacer()
                    Text("$")
                    TextField("0.00", value: $viewModel.payoutTotalSinceLast, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }

                Text("This total is allocated across shared voices by each voice's percentage of character usage since the selected payout date.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Text("Paste payout history (date/time + amount + currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $payoutPasteText)
                    .frame(minHeight: 120)
                    .font(.system(.caption, design: .monospaced))

                HStack {
                    Button("Import Payout Rows") {
                        payoutImportMessage = viewModel.importPayoutHistory(from: payoutPasteText)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Apply Latest Payout Cycle") {
                        viewModel.applyLatestPayoutCycle()
                        payoutImportMessage = "Applied latest payout cycle."
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.payoutRecords.count < 2)
                }

                if !payoutImportMessage.isEmpty {
                    Text(payoutImportMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Voice-Specific Custom Rates") {
                if viewModel.voices.isEmpty {
                    Text("Load voices first to set per-voice rates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.voices.filter(\.isShared).sorted(by: { $0.name < $1.name })) { voice in
                        VoiceRateOverrideRow(voice: voice)
                            .environmentObject(viewModel)
                    }
                }

                Text("These overrides apply only to the currently selected account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Auto-Refresh") {
                Picker("Refresh every", selection: $viewModel.pollingIntervalMinutes) {
                    ForEach(pollingOptions, id: \.minutes) { opt in
                        Text(opt.label).tag(opt.minutes)
                    }
                }

                Button("Refresh Now") {
                    Task { await viewModel.fetchAll() }
                }
                .buttonStyle(.bordered)

                if let updated = viewModel.lastUpdated {
                    Text("Last updated: \(updated.formatted())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Data Windows") {
                Stepper("Weekly lookback: \(AppSettings.lookbackWeeks) weeks",
                        value: Binding(
                            get: { AppSettings.lookbackWeeks },
                            set: { AppSettings.lookbackWeeks = $0 }
                        ),
                        in: 4...52,
                        step: 4)

                Stepper("Monthly lookback: \(AppSettings.lookbackMonths) months",
                        value: Binding(
                            get: { AppSettings.lookbackMonths },
                            set: { AppSettings.lookbackMonths = $0 }
                        ),
                        in: 3...36,
                        step: 3)
            }

            Section("Quick Links") {
                HStack(spacing: 12) {
                    QuickLinkButton(
                        title: "ElevenLabs Payouts",
                        icon: "dollarsign.circle",
                        url: "https://elevenlabs.io/app/payouts"
                    )
                    QuickLinkButton(
                        title: "My Voices",
                        icon: "waveform",
                        url: "https://elevenlabs.io/app/voice-lab/instant-voice-cloning"
                    )
                    QuickLinkButton(
                        title: "API Keys",
                        icon: "key",
                        url: "https://elevenlabs.io/app/settings/api-keys"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

struct AccountRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let account: ElevenLabsAccount

    @State private var name = ""
    @State private var key = ""
    @State private var showKey = false

    var isSelected: Bool {
        viewModel.selectedAccountID == account.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Account name", text: $name)
                    .textFieldStyle(.roundedBorder)

                if isSelected {
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
            }

            HStack {
                if showKey {
                    TextField("Update API key (optional)", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    SecureField("Update API key (optional)", text: $key)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button(isSelected ? "Using" : "Use Account") {
                    viewModel.selectAccount(accountID: account.id)
                }
                .buttonStyle(.bordered)
                .disabled(isSelected)

                Button("Save") {
                    let keyToSave = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.updateAccount(accountID: account.id, name: name, apiKey: keyToSave.isEmpty ? nil : keyToSave)
                    key = ""
                }
                .buttonStyle(.borderedProminent)

                Button("Remove") {
                    viewModel.removeAccount(accountID: account.id)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .onAppear {
            name = account.name
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick Link Button

struct QuickLinkButton: View {
    let title: String
    let icon: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.purple)
                Text(title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct VoiceRateOverrideRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    let voice: Voice
    @State private var value: String = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(.subheadline)
                if let custom = viewModel.customRate(for: voice) {
                    Text("Custom: $\(String(format: "%.6f", custom))/1k")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(viewModel.rateSourceLabel(for: voice)): $\(String(format: "%.6f", viewModel.ratePerThousandUsed(for: voice)))/1k")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            TextField("0.008010", text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
                .onSubmit { commitRate() }

            Button("Save") { commitRate() }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Clear") {
                value = ""
                viewModel.setCustomRate(nil, for: voice)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.customRate(for: voice) == nil)
        }
        .onAppear {
                if let custom = viewModel.customRate(for: voice) {
                    value = String(format: "%.6f", custom)
                }
            }
    }

    private func commitRate() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            viewModel.setCustomRate(nil, for: voice)
            return
        }
        if let parsed = Double(trimmed), parsed > 0 {
            viewModel.setCustomRate(parsed, for: voice)
            value = String(format: "%.6f", parsed)
        }
    }
}
