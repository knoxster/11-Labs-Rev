// AppViewModel.swift
// ElevenLabsDashboard
//
// Central observable state. Drives all views and manages polling timer.

import SwiftUI
import Combine

@MainActor
class AppViewModel: ObservableObject {

    // MARK: - Published State

    @Published var voices: [Voice] = []
    @Published var professionalVoices: [Voice] = []
    @Published var user: UserResponse?

    @Published var weeklyUsage: UsageResponse?
    @Published var monthlyUsage: UsageResponse?
    @Published var allTimeUsage: UsageResponse?

    @Published var weeklyEarnings: [VoiceEarnings] = []
    @Published var monthlyEarnings: [VoiceEarnings] = []
    @Published var allTimeEarnings: [VoiceEarnings] = []

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    @Published var apiKey: String = "" {
        didSet {
            if apiKey != oldValue {
                KeychainService.save(apiKey)
            }
        }
    }

    @Published var ratePerThousand: Double = AppSettings.ratePerThousandChars {
        didSet { AppSettings.ratePerThousandChars = ratePerThousand }
    }

    @Published var pollingIntervalMinutes: Double = AppSettings.pollingInterval / 60 {
        didSet {
            AppSettings.pollingInterval = pollingIntervalMinutes * 60
            restartTimer()
        }
    }

    @Published var manualPendingBalance: Double = AppSettings.manualPendingBalance {
        didSet { AppSettings.manualPendingBalance = manualPendingBalance }
    }

    // MARK: - Private

    private let service = ElevenLabsService()
    private var pollingTimer: AnyCancellable?

    // MARK: - Init

    init() {
        apiKey = KeychainService.load() ?? ""
        ratePerThousand = AppSettings.ratePerThousandChars
        pollingIntervalMinutes = AppSettings.pollingInterval / 60
        manualPendingBalance = AppSettings.manualPendingBalance

        if !apiKey.isEmpty {
            Task { await fetchAll() }
        }
        startTimer()
    }

    // MARK: - Computed

    /// Total estimated earnings for this month, across all voices
    var totalMonthlyEstimated: Double {
        monthlyEarnings.reduce(0) { $0 + $1.estimatedEarnings }
    }

    /// Total estimated earnings for this week
    var totalWeeklyEstimated: Double {
        weeklyEarnings.reduce(0) { $0 + $1.estimatedEarnings }
    }

    /// All-time estimated earnings
    var totalAllTimeEstimated: Double {
        allTimeEarnings.reduce(0) { $0 + $1.estimatedEarnings }
    }

    /// The display string shown in menu bar and window title
    var displayPayoutString: String {
        if manualPendingBalance > 0 {
            return "Pending: \(manualPendingBalance.asFormattedEarnings())"
        }
        return "~\(totalMonthlyEstimated.asFormattedEarnings())/mo"
    }

    /// Short form for menu bar (space-constrained)
    var menuBarTitle: String {
        if manualPendingBalance > 0 {
            return manualPendingBalance.asFormattedEarnings()
        }
        return "~\(totalMonthlyEstimated.asFormattedEarnings())"
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Data Fetching

    func fetchAll() async {
        guard hasAPIKey else {
            errorMessage = "Please configure your ElevenLabs API key in Settings."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let voicesTask   = service.getVoices(apiKey: apiKey)
            async let userTask     = service.getUser(apiKey: apiKey)

            let (fetchedVoices, fetchedUser) = try await (voicesTask, userTask)
            voices = fetchedVoices
            professionalVoices = fetchedVoices.filter { $0.isProfessionalClone }
            user = fetchedUser

            // Now fetch usage with appropriate windows
            await fetchUsage()

            lastUpdated = Date()
            updateWindowTitle()

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func fetchUsage() async {
        guard hasAPIKey else { return }

        let now = Date()
        let calendar = Calendar.current

        // Weekly window: past N weeks
        let weeksBack = AppSettings.lookbackWeeks
        let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: now) ?? now

        // Monthly window: past N months
        let monthsBack = AppSettings.lookbackMonths
        let monthStart = calendar.date(byAdding: .month, value: -monthsBack, to: now) ?? now

        // All-time: past 3 years
        let allTimeStart = calendar.date(byAdding: .year, value: -3, to: now) ?? now

        do {
            async let weeklyTask   = service.getUsage(start: weekStart,    end: now, aggregation: "week",        apiKey: apiKey)
            async let monthlyTask  = service.getUsage(start: monthStart,   end: now, aggregation: "month",       apiKey: apiKey)
            async let allTimeTask  = service.getUsage(start: allTimeStart, end: now, aggregation: "cumulative",  apiKey: apiKey)

            let (weekly, monthly, allTime) = try await (weeklyTask, monthlyTask, allTimeTask)

            weeklyUsage  = weekly
            monthlyUsage = monthly
            allTimeUsage = allTime

            // Recompute earnings
            weeklyEarnings  = ElevenLabsService.computeEarnings(from: weekly,  voices: voices, ratePerThousand: ratePerThousand)
            monthlyEarnings = ElevenLabsService.computeEarnings(from: monthly, voices: voices, ratePerThousand: ratePerThousand)
            allTimeEarnings = ElevenLabsService.computeEarnings(from: allTime, voices: voices, ratePerThousand: ratePerThousand)

        } catch {
            errorMessage = "Usage fetch failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Polling Timer

    private func startTimer() {
        pollingTimer = Timer.publish(
            every: AppSettings.pollingInterval,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            Task { await self?.fetchAll() }
        }
    }

    private func restartTimer() {
        pollingTimer?.cancel()
        startTimer()
    }

    // MARK: - Window Title

    func updateWindowTitle() {
        DispatchQueue.main.async {
            NSApplication.shared.windows.forEach { window in
                window.title = "ElevenLabs — \(self.displayPayoutString)"
            }
        }
    }

    // MARK: - Helpers for Charts

    func weeklyBuckets(for voiceName: String? = nil) -> [EarningsBucket] {
        guard let usage = weeklyUsage else { return [] }
        return ElevenLabsService.makeBuckets(from: usage, ratePerThousand: ratePerThousand, voiceName: voiceName)
    }

    func monthlyBuckets(for voiceName: String? = nil) -> [EarningsBucket] {
        guard let usage = monthlyUsage else { return [] }
        return ElevenLabsService.makeBuckets(from: usage, ratePerThousand: ratePerThousand, voiceName: voiceName)
    }
}
