// DashboardView.swift
// ElevenLabsDashboard
//
// Overview screen:
// • Large payout / estimated earnings in the top-left (title bar value mirrors this)
// • Summary cards: weekly, monthly, all-time
// • Voice count + account info
// • Manual pending balance entry

import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showBalanceField = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Hero — Current Payout Display
                HeroPayoutCard()
                    .environmentObject(viewModel)

                // MARK: Summary Cards
                HStack(spacing: 16) {
                    SummaryCard(
                        title: "This Week (Est.)",
                        value: viewModel.totalWeeklyEstimated.asFormattedEarnings(),
                        subtitle: "\(viewModel.weeklyEarnings.count) voice(s) earning",
                        icon: "calendar.badge.clock",
                        color: .orange
                    )
                    SummaryCard(
                        title: "This Month (Est.)",
                        value: viewModel.totalMonthlyEstimated.asFormattedEarnings(),
                        subtitle: "\(viewModel.monthlyEarnings.count) voice(s) earning",
                        icon: "calendar",
                        color: .blue
                    )
                    SummaryCard(
                        title: "All-Time (Est.)",
                        value: viewModel.totalAllTimeEstimated.asFormattedEarnings(),
                        subtitle: "\(viewModel.professionalVoices.count) professional voice(s)",
                        icon: "chart.line.uptrend.xyaxis",
                        color: .purple
                    )
                }

                // MARK: Account Info
                if let user = viewModel.user {
                    AccountInfoRow(user: user)
                }

                // MARK: Professional Voices List
                if !viewModel.professionalVoices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Professional Voice Clones")
                            .font(.headline)
                            .padding(.bottom, 2)

                        ForEach(viewModel.professionalVoices) { voice in
                            VoiceRow(voice: voice, viewModel: viewModel)
                        }
                    }
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                }

                // MARK: API Limitation Notice
                APILimitationNotice()

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .onChange(of: viewModel.totalMonthlyEstimated) { _ in
            viewModel.updateWindowTitle()
        }
        .onChange(of: viewModel.manualPendingBalance) { _ in
            viewModel.updateWindowTitle()
        }
        .onAppear {
            viewModel.updateWindowTitle()
        }
    }
}

// MARK: - Hero Payout Card

struct HeroPayoutCard: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var editingBalance = false
    @State private var balanceInput = ""

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {

                // Label
                Label(
                    viewModel.manualPendingBalance > 0
                    ? "Pending Payout (Manual)"
                    : "Estimated Monthly Earnings",
                    systemImage: "dollarsign.circle.fill"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)

                // The BIG number — this is what shows top-left
                Text(
                    viewModel.manualPendingBalance > 0
                    ? viewModel.manualPendingBalance.asFormattedEarnings()
                    : viewModel.totalMonthlyEstimated.asFormattedEarnings()
                )
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

                // Sub-label
                Text(
                    viewModel.manualPendingBalance > 0
                    ? "Entered manually from your Stripe dashboard"
                    : "Based on character usage × $\(String(format: "%.4f", viewModel.ratePerThousand))/1k chars"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Enter Stripe balance manually
            VStack(alignment: .trailing, spacing: 8) {
                Text("Stripe Pending Balance")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if editingBalance {
                    HStack {
                        TextField("0.00", text: $balanceInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .onSubmit { commitBalance() }

                        Button("Save") { commitBalance() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        Button("Cancel") { editingBalance = false }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(viewModel.manualPendingBalance > 0
                             ? viewModel.manualPendingBalance.asFormattedEarnings()
                             : "Not set")
                            .font(.title3.bold())

                        Button(viewModel.manualPendingBalance > 0 ? "Update" : "Enter") {
                            balanceInput = viewModel.manualPendingBalance > 0
                                ? String(format: "%.2f", viewModel.manualPendingBalance)
                                : ""
                            editingBalance = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if viewModel.manualPendingBalance > 0 {
                            Button("Clear") {
                                viewModel.manualPendingBalance = 0
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.red)
                        }
                    }
                }

                Link("Open Stripe Dashboard ↗",
                     destination: URL(string: "https://dashboard.stripe.com/balance/overview")!)
                    .font(.caption)
                    .foregroundColor(.purple)
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.12), Color.blue.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }

    private func commitBalance() {
        if let value = Double(balanceInput) {
            viewModel.manualPendingBalance = value
        }
        editingBalance = false
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Account Info Row

struct AccountInfoRow: View {
    let user: UserResponse

    var body: some View {
        HStack(spacing: 20) {
            if let name = user.firstName {
                Label(name + (user.lastName.map { " \($0)" } ?? ""),
                      systemImage: "person.fill")
                    .font(.subheadline)
            }
            if let tier = user.subscriptionTier {
                Label(tier.capitalized, systemImage: "crown.fill")
                    .font(.subheadline)
                    .foregroundColor(.yellow)
            }
            if let count = user.characterCount, let limit = user.characterLimit {
                Label("\(count.formatted()) / \(limit.formatted()) chars used",
                      systemImage: "chart.bar.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Voice Row

struct VoiceRow: View {
    let voice: Voice
    @ObservedObject var viewModel: AppViewModel

    var monthlyEarning: VoiceEarnings? {
        viewModel.monthlyEarnings.first { $0.voice.voiceId == voice.voiceId || $0.voice.name == voice.name }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    if voice.isShared {
                        Label("Shared", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    if let rate = voice.sharingRate {
                        Text("$\(String(format: "%.4f", rate))/1k chars")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            if let earning = monthlyEarning {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(earning.estimatedEarnings.asFormattedEarnings())
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                    Text("this month")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No data yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - API Limitation Notice

struct APILimitationNotice: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ElevenLabs does not expose Voice Library payout balances via their public REST API — payouts flow through Stripe Connect and are only visible in the ElevenLabs web UI or your Stripe dashboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("This app shows **estimated earnings** calculated from character usage data × your configured rate. Use the 'Stripe Pending Balance' field above to manually enter your known balance from Stripe.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Link("View Payouts on ElevenLabs ↗",
                         destination: URL(string: "https://elevenlabs.io/app/payouts")!)
                        .font(.caption)

                    Link("Stripe Dashboard ↗",
                         destination: URL(string: "https://dashboard.stripe.com/balance/overview")!)
                        .font(.caption)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("About Earnings Estimates", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
