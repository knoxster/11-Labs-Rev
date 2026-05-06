// VoiceComparisonView.swift
// ElevenLabsDashboard
//
// Side-by-side comparison of revenue across all professional voice clones.
// Includes a stacked bar chart and a ranked table.

import SwiftUI
import Charts

struct VoiceComparisonView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedPeriod: EarningsPeriod = .month
    @State private var chartType: ChartType = .bar
    @State private var sortOrder: SortOrder = .earnings

    enum ChartType: String, CaseIterable {
        case bar = "Bar"
        case line = "Line"
        case pie = "Pie"
    }

    enum SortOrder: String, CaseIterable {
        case earnings = "Earnings"
        case characters = "Characters"
        case name = "Name"
    }

    var earnings: [VoiceEarnings] {
        let base = selectedPeriod == .week
            ? viewModel.weeklyEarnings
            : viewModel.monthlyEarnings

        switch sortOrder {
        case .earnings:   return base.sorted { $0.estimatedEarnings > $1.estimatedEarnings }
        case .characters: return base.sorted { $0.characterCount > $1.characterCount }
        case .name:       return base.sorted { $0.voice.name < $1.voice.name }
        }
    }

    var buckets: [EarningsBucket] {
        selectedPeriod == .week
            ? viewModel.weeklyBuckets()
            : viewModel.monthlyBuckets()
    }

    var topEarner: VoiceEarnings? { earnings.first }
    var total: Double { earnings.reduce(0) { $0 + $1.estimatedEarnings } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Toolbar row
                HStack {
                    Text("Revenue Comparison")
                        .font(.title2.bold())

                    Spacer()

                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(EarningsPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Picker("Chart", selection: $chartType) {
                        ForEach(ChartType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)

                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                // MARK: Top-line stats
                HStack(spacing: 16) {
                    CompactStatCard(
                        title: "Total \(selectedPeriod.rawValue)",
                        value: total.asFormattedEarnings(),
                        color: .blue
                    )
                    if let top = topEarner {
                        CompactStatCard(
                            title: "Top Voice",
                            value: top.voice.name,
                            color: .purple
                        )
                        CompactStatCard(
                            title: "Top Earnings",
                            value: top.estimatedEarnings.asFormattedEarnings(),
                            color: .green
                        )
                    }
                    CompactStatCard(
                        title: "Voices Compared",
                        value: "\(earnings.count)",
                        color: .orange
                    )
                }

                if earnings.isEmpty {
                    ContentUnavailableView(
                        "No Comparison Data",
                        systemImage: "chart.bar.xaxis",
                        description: Text("No character usage data found. Make sure your professional voice clones are shared in the Voice Library and have been used by other users.")
                    )
                    .frame(height: 300)
                } else {
                    // MARK: Main Chart
                    switch chartType {
                    case .bar:  BarComparisonChart(earnings: earnings)
                    case .line: LineComparisonChart(buckets: buckets, period: selectedPeriod)
                    case .pie:  PieComparisonChart(earnings: earnings, total: total)
                    }

                    // MARK: Ranked Table
                    RankedEarningsTable(earnings: earnings, total: total)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .navigationTitle("Voice Comparison")
    }
}

// MARK: - Bar Chart

struct BarComparisonChart: View {
    let earnings: [VoiceEarnings]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Earnings by Voice")
                .font(.headline)

            Chart(earnings) { e in
                BarMark(
                    x: .value("Voice", e.voice.name),
                    y: .value("Earnings", e.estimatedEarnings)
                )
                .foregroundStyle(by: .value("Voice", e.voice.name))
                .annotation(position: .top, alignment: .center) {
                    Text(e.estimatedEarnings.asFormattedEarnings())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
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
            .chartLegend(.hidden)
            .frame(height: 300)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Line Chart (over time, all voices)

struct LineComparisonChart: View {
    let buckets: [EarningsBucket]
    let period: EarningsPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Earnings Over Time — All Voices")
                .font(.headline)

            if buckets.isEmpty {
                Text("No time-series data available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart(buckets) { b in
                    LineMark(
                        x: .value("Date", b.date, unit: period == .week ? .weekOfYear : .month),
                        y: .value("Earnings", b.earnings)
                    )
                    .foregroundStyle(by: .value("Voice", b.voiceName))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", b.date, unit: period == .week ? .weekOfYear : .month),
                        y: .value("Earnings", b.earnings)
                    )
                    .foregroundStyle(by: .value("Voice", b.voiceName))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: period == .week ? .weekOfYear : .month)) { v in
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
                .frame(height: 300)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Pie / Donut Chart

struct PieComparisonChart: View {
    let earnings: [VoiceEarnings]
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Earnings Share by Voice")
                .font(.headline)

            HStack(spacing: 24) {
                Chart(earnings) { e in
                    SectorMark(
                        angle: .value("Earnings", e.estimatedEarnings),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Voice", e.voice.name))
                    .cornerRadius(4)
                }
                .frame(width: 260, height: 260)

                // Legend
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(earnings) { e in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colorFor(index: earnings.firstIndex(where: { $0.id == e.id }) ?? 0))
                                .frame(width: 10, height: 10)

                            Text(e.voice.name)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 0) {
                                Text(e.estimatedEarnings.asFormattedEarnings())
                                    .font(.caption.bold())
                                Text(String(format: "%.1f%%", total > 0 ? (e.estimatedEarnings / total * 100) : 0))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func colorFor(index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .red, .yellow, .pink, .teal, .indigo, .mint]
        return colors[index % colors.count]
    }
}

// MARK: - Ranked Earnings Table

struct RankedEarningsTable: View {
    let earnings: [VoiceEarnings]
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ranked Breakdown")
                .font(.headline)

            // Column headers
            HStack {
                Text("#").frame(width: 24)
                Text("Voice").frame(maxWidth: .infinity, alignment: .leading)
                Text("Characters").frame(width: 110, alignment: .trailing)
                Text("Share").frame(width: 60, alignment: .trailing)
                Text("Est. Earnings").frame(width: 110, alignment: .trailing)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)

            Divider()

            ForEach(Array(earnings.enumerated()), id: \.element.id) { index, earning in
                HStack {
                    // Rank
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 24)

                    // Voice name + share badge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(earning.voice.name)
                            .font(.subheadline.bold())
                        if earning.voice.isShared {
                            Text("Shared")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Characters
                    Text(Int(earning.characterCount).formatted())
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 110, alignment: .trailing)

                    // Share bar + %
                    HStack(spacing: 4) {
                        let pct = total > 0 ? earning.estimatedEarnings / total : 0
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: geo.size.width * pct, height: 6)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: 30, height: 14)

                        Text(String(format: "%.1f%%", total > 0 ? (earning.estimatedEarnings / total * 100) : 0))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 60, alignment: .trailing)

                    // Earnings
                    Text(earning.estimatedEarnings.asFormattedEarnings())
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundColor(.blue)
                        .frame(width: 110, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Compact Stat Card

struct CompactStatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline.bold())
                .foregroundColor(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
