// SettingsView.swift
// ElevenLabsDashboard
//
// Configure: API key, payout rate, polling interval, lookback windows.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var apiKeyInput = ""
    @State private var showAPIKey = false
    @State private var showSavedConfirmation = false

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

            // MARK: API Key
            Section("ElevenLabs API Key") {
                HStack {
                    if showAPIKey {
                        TextField("xi-api-key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("xi-api-key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Button("Save API Key") {
                        viewModel.apiKey = apiKeyInput.trimmingCharacters(in: .whitespaces)
                        showSavedConfirmation = true
                        Task { await viewModel.fetchAll() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                    if showSavedConfirmation {
                        Label("Saved!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                            .transition(.opacity)
                    }

                    Spacer()

                    Link("Get API Key ↗",
                         destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                        .font(.caption)
                }

                Text("Your API key is stored securely in the macOS Keychain. It is never sent anywhere other than api.elevenlabs.io.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: Payout Rate
            Section("Payout Rate") {
                HStack {
                    Text("Rate per 1,000 characters")
                    Spacer()
                    HStack(spacing: 4) {
                        Text("$")
                        TextField("0.0300", value: $viewModel.ratePerThousand, format: .number.precision(.fractionLength(4)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }

                Text("ElevenLabs pays voice creators based on the notice period you selected when sharing your voice. Your default rate is $0.03/1k chars (immediate removal). Longer notice periods earn higher rates. Find your exact rate in My Voices → View → Sharing Options.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link("Find my rate on ElevenLabs ↗",
                     destination: URL(string: "https://elevenlabs.io/app/voice-library")!)
                    .font(.caption)
            }

            // MARK: Polling Interval
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

            // MARK: Lookback Windows
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

                Text("Larger windows show more history but may take slightly longer to load.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: Quick Links
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
                        title: "Stripe Dashboard",
                        icon: "creditcard",
                        url: "https://dashboard.stripe.com/balance/overview"
                    )
                }
            }

            // MARK: About
            Section("About") {
                HStack {
                    Text("ElevenLabs Payout Dashboard")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("v1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("Built using the official ElevenLabs REST API. Earnings are estimated from character usage data × your configured rate. Actual payout balances are managed by Stripe Connect.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            apiKeyInput = viewModel.apiKey
        }
        .animation(.easeInOut(duration: 0.3), value: showSavedConfirmation)
        .onChange(of: showSavedConfirmation) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    showSavedConfirmation = false
                }
            }
        }
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
