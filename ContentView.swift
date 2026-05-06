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
        case settings   = "Settings"

        var icon: String {
            switch self {
            case .dashboard:  return "chart.pie.fill"
            case .byVoice:    return "waveform"
            case .comparison: return "chart.bar.xaxis"
            case .settings:   return "gearshape.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // MARK: Sidebar
            List(selection: $selectedTab) {
                Section("Overview") {
                    ForEach([Tab.dashboard, .byVoice, .comparison], id: \.self) { tab in
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
            // MARK: Detail Pane
            Group {
                switch selectedTab {
                case .dashboard:  DashboardView()
                case .byVoice:    EarningsByVoiceView()
                case .comparison: VoiceComparisonView()
                case .settings:   SettingsView()
                }
            }
            .environmentObject(viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Show API key prompt if needed
        .overlay {
            if !viewModel.hasAPIKey {
                NoAPIKeyBanner()
                    .environmentObject(viewModel)
            }
        }
        // Toolbar
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

// MARK: - No API Key Banner

struct NoAPIKeyBanner: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.purple)

                Text("API Key Required")
                    .font(.title2.bold())

                Text("Add your ElevenLabs API key in Settings to get started.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 320)

                HStack(spacing: 12) {
                    Button("Open Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .buttonStyle(.borderedProminent)

                    Link("Get API Key ↗", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                        .buttonStyle(.bordered)
                }
            }
            .padding(40)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
