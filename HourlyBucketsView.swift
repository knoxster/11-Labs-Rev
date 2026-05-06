// HourlyBucketsView.swift
// ElevenLabsDashboard
//
// Shows cached per-voice hourly usage for the last 24 hours.

import SwiftUI
import Charts

struct HourlyBucketsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedVoiceID: String?
    @State private var selectedMetric: HourlyChartMetric = .earnings

    private var voicesWithBuckets: [Voice] {
        let voiceIds = Set(viewModel.recentHourlyVoiceBuckets.map(\.voiceId))
        return viewModel.professionalVoices
            .filter { voiceIds.contains($0.voiceId) }
            .sorted { $0.name < $1.name }
    }

    private var selectedVoice: Voice? {
        guard let selectedVoiceID else { return nil }
        return voicesWithBuckets.first { $0.voiceId == selectedVoiceID }
    }

    private var buckets: [HourlyVoiceBucket] {
        viewModel.recentHourlyBuckets(for: selectedVoiceID)
    }

    private var totalCharacters: Double {
        buckets.reduce(0) { $0 + $1.characters }
    }

    private var totalEarnings: Double {
        buckets.reduce(0) { $0 + $1.estimatedEarnings }
    }

    private var totalRequests: Double {
        buckets.reduce(0) { $0 + ($1.requestCount ?? 0) }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("24 Hours", systemImage: "clock")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.recentHourlyVoiceBuckets.count) buckets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)

                Divider()

                List(selection: $selectedVoiceID) {
                    Button {
                        selectedVoiceID = nil
                    } label: {
                        HourlyVoiceRow(
                            title: "All voices",
                            characters: viewModel.recentHourlyVoiceBuckets.reduce(0) { $0 + $1.characters },
                            requests: viewModel.totalLast24HourRequests,
                            earnings: viewModel.totalLast24HourEstimated
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(voicesWithBuckets) { voice in
                        let voiceBuckets = viewModel.recentHourlyBuckets(for: voice.voiceId)
                        HourlyVoiceRow(
                            title: voice.name,
                            characters: voiceBuckets.reduce(0) { $0 + $1.characters },
                            requests: voiceBuckets.reduce(0) { $0 + ($1.requestCount ?? 0) },
                            earnings: voiceBuckets.reduce(0) { $0 + $1.estimatedEarnings }
                        )
                        .tag(voice.voiceId)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 240, maxWidth: 320)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedVoice?.name ?? "All Voices")
                                .font(.title2.bold())
                            Text("Hourly buckets from the cached last-24-hour window")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(totalEarnings.asFormattedEarnings())
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                            Text("\(Int(totalCharacters).formatted()) chars • \(Int(totalRequests).formatted()) requests")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if buckets.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No hourly buckets yet")
                                .font(.headline)
                            Text("Refresh once to fetch and cache the latest hourly usage.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        HStack {
                            Text("Chart")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Chart", selection: $selectedMetric) {
                                ForEach(HourlyChartMetric.allCases) { metric in
                                    Text(metric.rawValue).tag(metric)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 360)
                        }
                        HourlyMetricChart(buckets: buckets, metric: selectedMetric)
                        HourlyBucketTable(buckets: buckets)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("24-Hour Buckets")
    }
}

struct HourlyVoiceRow: View {
    let title: String
    let characters: Double
    let requests: Double
    let earnings: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
                .lineLimit(1)
            HStack {
                Text(earnings.asFormattedEarnings())
                    .font(.body.bold())
                    .foregroundColor(.blue)
                Spacer()
                Text("\(Int(characters).formatted()) chars • \(Int(requests).formatted()) req")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

enum HourlyChartMetric: String, CaseIterable, Identifiable {
    case earnings = "Earnings"
    case characters = "Characters"
    case requests = "Requests"

    var id: String { rawValue }

    func value(for bucket: HourlyVoiceBucket) -> Double {
        switch self {
        case .earnings:
            return bucket.estimatedEarnings
        case .characters:
            return bucket.characters
        case .requests:
            return bucket.requestCount ?? 0
        }
    }

    func formattedValue(_ value: Double) -> String {
        switch self {
        case .earnings:
            return value.asFormattedEarnings()
        case .characters:
            return Int(value).formatted()
        case .requests:
            return "\(Int(value).formatted()) req"
        }
    }
}

struct HourlyMetricChart: View {
    let buckets: [HourlyVoiceBucket]
    let metric: HourlyChartMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hourly \(metric.rawValue)")
                .font(.headline)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Hour", bucket.timestamp, unit: .hour),
                    y: .value(metric.rawValue, metric.value(for: bucket))
                )
                .foregroundStyle(by: .value("Voice", bucket.voiceName))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(metric.formattedValue(amount))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 280)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct HourlyBucketTable: View {
    let buckets: [HourlyVoiceBucket]

    private var rows: [HourlyVoiceBucket] {
        buckets.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.voiceName < $1.voiceName
            }
            return $0.timestamp > $1.timestamp
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hourly Buckets")
                .font(.headline)

            HStack {
                Text("Hour").frame(width: 90, alignment: .leading)
                Text("Voice").frame(maxWidth: .infinity, alignment: .leading)
                Text("Characters").frame(width: 110, alignment: .trailing)
                Text("Requests").frame(width: 90, alignment: .trailing)
                Text("Est. Earnings").frame(width: 120, alignment: .trailing)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)

            Divider()

            ForEach(rows) { bucket in
                HStack {
                    Text(bucket.timestamp.formatted(date: .omitted, time: .shortened))
                        .frame(width: 90, alignment: .leading)
                    Text(bucket.voiceName)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Int(bucket.characters).formatted())
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 110, alignment: .trailing)
                    Text(Int(bucket.requestCount ?? 0).formatted())
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 90, alignment: .trailing)
                    Text(bucket.estimatedEarnings.asFormattedEarnings())
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundColor(.blue)
                        .frame(width: 120, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}
