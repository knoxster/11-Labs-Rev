// EarningsByVoiceView.swift
// ElevenLabsDashboard
//
// Shows earnings broken down by voice, with a week/month toggle.
// Uses SwiftUI Charts (macOS 13+).

import SwiftUI
import Charts

struct EarningsByVoiceView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedPeriod: EarningsPeriod = .month
    @State private var selectedVoice: Voice?

    var earnings: [VoiceEarnings] {
        selectedPeriod == .week
            ? viewModel.weeklyEarnings
            : viewModel.monthlyEarnings
    }

    var buckets: [EarningsBucket] {
        let name = selectedVoice?.name
        return selectedPeriod == .week
            ? viewModel.weeklyBuckets(for: name)
            : viewModel.monthlyBuckets(for: name)
    }

    var periodTotal: Double {
        earnings.reduce(0) { $0 + $1.estimatedEarnings }
    }

    var body: some View {
        HSplitView {
            // MARK: Left — Voice List
            VStack(alignment: .leading, spacing: 0) {
                // Period picker
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(EarningsPeriod.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)

                Divider()

                // Total for period
                HStack {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(periodTotal.asFormattedEarnings())
                        .font(.subheadline.bold())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Voice list
                if earnings.isEmpty {
                    Spacer()
                    Text("No earnings data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    List(selection: $selectedVoice) {
                        ForEach(earnings) { earning in
                            EarningsListRow(earning: earning)
                                .tag(earning.voice)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 240, maxWidth: 300)

            // MARK: Right — Chart Detail
            if let selected = selectedVoice {
                VoiceDetailChart(
                    voice: selected,
                    buckets: buckets,
                    period: selectedPeriod
                )
            } else {
                AllVoicesChart(earnings: earnings, buckets: buckets, period: selectedPeriod)
            }
        }
        .navigationTitle("Earnings by Voice")
    }
}

// MARK: - Earnings List Row

struct EarningsListRow: View {
    let earning: VoiceEarnings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(earning.voice.name)
                .font(.subheadline.bold())
                .lineLimit(1)

            HStack {
                Text(earning.estimatedEarnings.asFormattedEarnings())
                    .font(.body.bold())
                    .foregroundColor(.blue)

                Spacer()

                Text("\(Int(earning.characterCount).formatted()) chars")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Mini progress bar relative to top earner (set externally if needed)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: geo.size.width, height: 3)
            }
            .frame(height: 3)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - All Voices Chart (overview)

struct AllVoicesChart: View {
    let earnings: [VoiceEarnings]
    let buckets: [EarningsBucket]
    let period: EarningsPeriod

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("All Voices — \(period.rawValue)")
                    .font(.title2.bold())
                    .padding(.top, 4)

                // Bar chart: earnings per voice
                if !earnings.isEmpty {
                    Chart(earnings) { e in
                        BarMark(
                            x: .value("Earnings", e.estimatedEarnings),
                            y: .value("Voice", e.voice.name)
                        )
                        .foregroundStyle(by: .value("Voice", e.voice.name))
                        .annotation(position: .trailing) {
                            Text(e.estimatedEarnings.asFormattedEarnings())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text(d.asFormattedEarnings())
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: CGFloat(earnings.count) * 44 + 40)
                }

                // Time-series chart: earnings over time
                if !buckets.isEmpty {
                    Text("Earnings Over Time")
                        .font(.headline)

                    Chart(buckets) { b in
                        LineMark(
                            x: .value("Date", b.date),
                            y: .value("Earnings", b.earnings)
                        )
                        .foregroundStyle(by: .value("Voice", b.voiceName))

                        AreaMark(
                            x: .value("Date", b.date),
                            y: .value("Earnings", b.earnings)
                        )
                        .foregroundStyle(by: .value("Voice", b.voiceName))
                        .opacity(0.15)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: period == .week ? .weekOfYear : .month)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: period == .week ? .dateTime.month().day() : .dateTime.month().year())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text(d.asFormattedEarnings()).font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }
}

// MARK: - Single Voice Detail Chart

struct VoiceDetailChart: View {
    let voice: Voice
    let buckets: [EarningsBucket]
    let period: EarningsPeriod

    var voiceBuckets: [EarningsBucket] {
        buckets.filter { $0.voiceName == voice.name }
    }

    var totalEarnings: Double {
        voiceBuckets.reduce(0) { $0 + $1.earnings }
    }

    var totalChars: Double {
        voiceBuckets.reduce(0) { $0 + $1.characters }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(voice.name)
                            .font(.title.bold())
                        if voice.isShared {
                            Label("Shared in Voice Library", systemImage: "globe")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(totalEarnings.asFormattedEarnings())
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                        Text("\(period.rawValue) Estimated")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Stats row
                HStack(spacing: 20) {
                    StatBadge(label: "Characters", value: Int(totalChars).formatted(), color: .purple)
                    if let rate = voice.sharingRate {
                        StatBadge(label: "Your Rate", value: "$\(String(format: "%.4f", rate))/1k", color: .orange)
                    }
                    StatBadge(label: "Buckets", value: "\(voiceBuckets.count)", color: .gray)
                }

                // Chart
                if !voiceBuckets.isEmpty {
                    Text("Earnings Over Time")
                        .font(.headline)

                    Chart(voiceBuckets) { b in
                        BarMark(
                            x: .value("Date", b.date, unit: period == .week ? .weekOfYear : .month),
                            y: .value("Earnings", b.earnings)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: period == .week ? .weekOfYear : .month)) { value in
                            AxisGridLine()
                            AxisValueLabel(
                                format: period == .week ? .dateTime.month().day() : .dateTime.month()
                            )
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text(d.asFormattedEarnings()).font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 240)

                    // Character usage chart
                    Text("Character Usage")
                        .font(.headline)

                    Chart(voiceBuckets) { b in
                        LineMark(
                            x: .value("Date", b.date, unit: period == .week ? .weekOfYear : .month),
                            y: .value("Characters", b.characters)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.orange)

                        AreaMark(
                            x: .value("Date", b.date, unit: period == .week ? .weekOfYear : .month),
                            y: .value("Characters", b.characters)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.orange.opacity(0.15))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: period == .week ? .weekOfYear : .month)) { value in
                            AxisGridLine()
                            AxisValueLabel(
                                format: period == .week ? .dateTime.month().day() : .dateTime.month()
                            )
                        }
                    }
                    .frame(height: 160)

                } else {
                    ContentUnavailableView(
                        "No data for this period",
                        systemImage: "chart.xyaxis.line",
                        description: Text("This voice had no character usage in the selected period.")
                    )
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
