// ElevenLabsDashboardApp.swift
// ElevenLabsDashboard
//
// App entry point. Sets up the main window and the menu bar extra.
// Requires macOS 13+ for MenuBarExtra.

import SwiftUI

@main
struct ElevenLabsDashboardApp: App {

    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {

        // MARK: - Main Window
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    // Give the window a styled appearance
                    NSApp.windows.first?.titleVisibility = .visible
                    NSApp.windows.first?.titlebarAppearsTransparent = false
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Refresh Now") {
                    Task { await viewModel.fetchAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        // MARK: - Menu Bar Extra
        // Shows current payout / estimated earnings
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(viewModel)
        } label: {
            Label {
                Text(viewModel.menuBarTitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            } icon: {
                Image(systemName: "waveform.circle.fill")
            }
        }
        .menuBarExtraStyle(.window)

        // MARK: - Settings Window
        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .frame(width: 500)
        }
    }
}

// MARK: - Menu Bar Popover

struct MenuBarPopoverView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundColor(.purple)
                    .font(.title2)
                Text("ElevenLabs Dashboard")
                    .font(.headline)
                Spacer()
            }
            Divider()

            // Pending / monthly summary
            if viewModel.manualPendingBalance > 0 {
                SummaryRow(label: "Pending Balance",
                           value: viewModel.manualPendingBalance.asFormattedEarnings(),
                           icon: "dollarsign.circle.fill",
                           color: .green)
            }
            SummaryRow(label: "Est. This Month",
                       value: viewModel.totalMonthlyEstimated.asFormattedEarnings(),
                       icon: "calendar",
                       color: .blue)
            SummaryRow(label: "Est. This Week",
                       value: viewModel.totalWeeklyEstimated.asFormattedEarnings(),
                       icon: "chart.bar.fill",
                       color: .orange)

            Divider()

            // Top voice this month
            if let top = viewModel.monthlyEarnings.first {
                HStack {
                    Image(systemName: "star.fill").foregroundColor(.yellow)
                    Text("Top Voice: \(top.voice.name)")
                        .font(.caption)
                    Spacer()
                    Text(top.estimatedEarnings.asFormattedEarnings())
                        .font(.caption.bold())
                }
            }

            // Last updated
            if let updated = viewModel.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Button("Open Dashboard") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
                }
                Spacer()
                Button("Refresh") {
                    Task { await viewModel.fetchAll() }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - Summary Row

struct SummaryRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.primary)
        }
    }
}
