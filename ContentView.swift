// ContentView.swift
// ElevenLabsDashboard
//
// Main window: tab bar on the left, content on the right.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedTab: Tab = .dashboard

    enum Tab: String, CaseIterable {
        case dashboard  = "Dashboard"
        case byVoice    = "By Voice"
        case comparison = "Comparison"
        case hourly     = "24 Hours"
        case settings   = "Settings"

        var icon: String {
            switch self {
            case .dashboard:  return "chart.pie.fill"
            case .byVoice:    return "waveform"
            case .comparison: return "chart.bar.xaxis"
            case .hourly:     return "clock.fill"
            case .settings:   return "gearshape.fill"
            }
        }
    }

    private var requiresOnboarding: Bool {
        !viewModel.hasCompletedOnboarding || !viewModel.hasAPIKey
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Overview") {
                    ForEach([Tab.dashboard, .byVoice, .comparison, .hourly], id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                Section("App") {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                        .tag(Tab.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("ElevenLabs")
            .frame(minWidth: 180)
        } detail: {
            Group {
                switch selectedTab {
                case .dashboard:  DashboardView()
                case .byVoice:    EarningsByVoiceView()
                case .comparison: VoiceComparisonView()
                case .hourly:     HourlyBucketsView()
                case .settings:   SettingsView()
                }
            }
            .environmentObject(viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if requiresOnboarding {
                FirstRunSetupView()
                    .environmentObject(viewModel)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                } else {
                    Button {
                        Task { await viewModel.fetchAll() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh data (⌘R)")
                }

                if let updated = viewModel.lastUpdated {
                    Text(updated.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct FirstRunSetupView: View {
    @EnvironmentObject var viewModel: AppViewModel

    @State private var accountName = ""
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var rate = "0.008010"
    @State private var refreshMinutes: Double = 15
    @State private var weeklyLookback: Int = 12
    @State private var monthlyLookback: Int = 12

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome to ElevenLabs Dashboard")
                    .font(.title2.bold())

                Text("Set up your first account and defaults to get started.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Account name (example: Personal)", text: $accountName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if showAPIKey {
                        TextField("xi-api-key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("xi-api-key", text: $apiKey)
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
                    Text("Default rate per 1,000 chars")
                    Spacer()
                    Text("$")
                    TextField("0.008010", text: $rate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }

                Picker("Refresh every", selection: $refreshMinutes) {
                    Text("5 minutes").tag(5.0)
                    Text("15 minutes").tag(15.0)
                    Text("30 minutes").tag(30.0)
                    Text("1 hour").tag(60.0)
                }

                HStack {
                    Stepper("Weekly lookback: \(weeklyLookback) weeks", value: $weeklyLookback, in: 4...52, step: 4)
                    Stepper("Monthly lookback: \(monthlyLookback) months", value: $monthlyLookback, in: 3...36, step: 3)
                }

                HStack {
                    Link("Get API Key ↗", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                        .font(.caption)

                    Spacer()

                    Button("Complete Setup") {
                        let parsedRate = Double(rate) ?? AppSettings.defaultRatePerThousand
                        let created = viewModel.completeOnboarding(
                            accountName: accountName,
                            apiKey: apiKey,
                            defaultRatePerThousand: parsedRate,
                            refreshMinutes: refreshMinutes,
                            weeklyLookback: weeklyLookback,
                            monthlyLookback: monthlyLookback
                        )
                        if !created {
                            viewModel.errorMessage = "Setup failed. Please verify account name, API key, and account limit (up to 5)."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 600)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
