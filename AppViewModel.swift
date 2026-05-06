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
    @Published var payoutWindowUsage: UsageResponse?

    @Published var weeklyEarnings: [VoiceEarnings] = []
    @Published var monthlyEarnings: [VoiceEarnings] = []
    @Published var allTimeEarnings: [VoiceEarnings] = []
    @Published var payoutAllocatedEarnings: [VoiceEarnings] = []
    @Published var hourlyVoiceBuckets: [HourlyVoiceBucket] = []

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    @Published var accounts: [ElevenLabsAccount] = AppSettings.elevenLabsAccounts {
        didSet { AppSettings.elevenLabsAccounts = accounts }
    }

    @Published var selectedAccountID: String? = AppSettings.selectedAccountID {
        didSet {
            if selectedAccountID != oldValue {
                AppSettings.selectedAccountID = selectedAccountID
                clearFetchedData()
                customVoiceRates = loadAndNormalizeCustomRates(for: selectedAccountID)
                hourlyVoiceBuckets = AppSettings.hourlyVoiceBuckets(for: selectedAccountID)
                Task { await fetchAll() }
            }
        }
    }

    @Published var hasCompletedOnboarding: Bool = AppSettings.hasCompletedOnboarding {
        didSet { AppSettings.hasCompletedOnboarding = hasCompletedOnboarding }
    }

    @Published var ratePerThousand: Double = AppSettings.ratePerThousandChars {
        didSet {
            AppSettings.ratePerThousandChars = ratePerThousand
            recomputeEarnings()
        }
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
    @Published var lastPayoutDate: Date = AppSettings.lastPayoutDate {
        didSet {
            AppSettings.lastPayoutDate = lastPayoutDate
            Task { await fetchAll() }
        }
    }
    @Published var payoutTotalSinceLast: Double = AppSettings.payoutTotalSinceLast {
        didSet {
            AppSettings.payoutTotalSinceLast = payoutTotalSinceLast
            recomputePayoutAllocation()
        }
    }
    @Published var payoutWindowEndDate: Date = AppSettings.payoutWindowEndDate {
        didSet {
            AppSettings.payoutWindowEndDate = payoutWindowEndDate
            Task { await fetchAll() }
        }
    }
    @Published var payoutRecords: [PayoutRecord] = AppSettings.importedPayoutRecords {
        didSet { AppSettings.importedPayoutRecords = payoutRecords }
    }

    @Published var customVoiceRates: [String: Double] = [:] {
        didSet { persistCustomRates(customVoiceRates, for: selectedAccountID) }
    }

    // MARK: - Private

    private let service = ElevenLabsService()
    private var pollingTimer: AnyCancellable?
    private var sharedVoiceMetricsByVoiceID: [String: SharedVoice] = [:]

    // MARK: - Constants

    let maxAccounts = 5

    // MARK: - Init

    init() {
        migrateLegacyDefaultRateIfNeeded()

        ratePerThousand = AppSettings.ratePerThousandChars
        pollingIntervalMinutes = AppSettings.pollingInterval / 60
        manualPendingBalance = AppSettings.manualPendingBalance
        lastPayoutDate = AppSettings.lastPayoutDate
        payoutTotalSinceLast = AppSettings.payoutTotalSinceLast
        payoutWindowEndDate = AppSettings.payoutWindowEndDate

        migrateLegacyKeyIfNeeded()

        if selectedAccountID == nil, let first = accounts.first {
            selectedAccountID = first.id
        }
        customVoiceRates = loadAndNormalizeCustomRates(for: selectedAccountID)
        hourlyVoiceBuckets = AppSettings.hourlyVoiceBuckets(for: selectedAccountID)

        if hasAPIKey {
            Task { await fetchAll() }
        }

        startTimer()
    }

    // MARK: - Computed

    var activeAccount: ElevenLabsAccount? {
        guard let selectedAccountID else { return nil }
        return accounts.first(where: { $0.id == selectedAccountID })
    }

    var hasAPIKey: Bool {
        guard let accountID = selectedAccountID else { return false }
        guard let key = KeychainService.load(for: accountID) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

    /// Total payout allocated by shared-voice usage since last payout date
    var totalAllocatedPayoutSinceLast: Double {
        payoutAllocatedEarnings.reduce(0) { $0 + $1.estimatedEarnings }
    }

    var recentHourlyVoiceBuckets: [HourlyVoiceBucket] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return hourlyVoiceBuckets
            .filter { $0.timestamp >= cutoff }
            .sorted {
                if $0.timestamp == $1.timestamp {
                    return $0.voiceName < $1.voiceName
                }
                return $0.timestamp < $1.timestamp
            }
    }

    var totalLast24HourEstimated: Double {
        recentHourlyVoiceBuckets.reduce(0) { $0 + $1.estimatedEarnings }
    }

    var totalLast24HourRequests: Double {
        recentHourlyVoiceBuckets.reduce(0) { $0 + ($1.requestCount ?? 0) }
    }

    var lastThirtyOneDayPayoutRecords: [PayoutRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -31, to: Date()) ?? Date()
        return payoutRecords
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var lastThirtyOneDayPayoutCount: Int {
        lastThirtyOneDayPayoutRecords.count
    }

    var formattedLastThirtyOneDayPayoutTotal: String {
        let grouped = Dictionary(grouping: lastThirtyOneDayPayoutRecords, by: \.currencyCode)
        guard !grouped.isEmpty else { return 0.asFormattedEarnings() }

        return grouped
            .map { currency, records in
                let total = records.reduce(0) { $0 + $1.amount }
                return total.asFormattedCurrency(currency)
            }
            .sorted()
            .joined(separator: " + ")
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

    // MARK: - Account Management

    func addAccount(name: String, apiKey: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedKey.isEmpty else { return false }
        guard accounts.count < maxAccounts else { return false }

        let account = ElevenLabsAccount(id: UUID().uuidString, name: trimmedName)
        accounts.append(account)
        KeychainService.save(trimmedKey, for: account.id)

        if selectedAccountID == nil {
            selectedAccountID = account.id
        }

        return true
    }

    func updateAccount(accountID: String, name: String, apiKey: String?) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            accounts[idx].name = trimmedName
        }

        if let apiKey {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                KeychainService.save(trimmed, for: accountID)
            }
        }

        if selectedAccountID == accountID {
            Task { await fetchAll() }
        }
    }

    func removeAccount(accountID: String) {
        accounts.removeAll { $0.id == accountID }
        KeychainService.delete(for: accountID)
        deleteCustomRates(for: accountID)

        if selectedAccountID == accountID {
            selectedAccountID = accounts.first?.id
        }

        if accounts.isEmpty {
            clearFetchedData()
            hasCompletedOnboarding = false
        }
    }

    func selectAccount(accountID: String) {
        guard accounts.contains(where: { $0.id == accountID }) else { return }
        selectedAccountID = accountID
    }

    func completeOnboarding(
        accountName: String,
        apiKey: String,
        defaultRatePerThousand: Double,
        refreshMinutes: Double,
        weeklyLookback: Int,
        monthlyLookback: Int
    ) -> Bool {
        let created = addAccount(name: accountName, apiKey: apiKey)
        guard created else { return false }

        ratePerThousand = max(defaultRatePerThousand, 0.0001)
        pollingIntervalMinutes = max(refreshMinutes, 5)
        AppSettings.lookbackWeeks = weeklyLookback
        AppSettings.lookbackMonths = monthlyLookback

        hasCompletedOnboarding = true
        Task { await fetchAll() }

        return true
    }

    @discardableResult
    func importPayoutHistory(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "M/d/yy, HH:mm"

        var parsed: [PayoutRecord] = []
        var index = 0
        while index < lines.count - 1 {
            let dateLine = lines[index]
            guard let timestamp = dateFormatter.date(from: dateLine) else {
                index += 1
                continue
            }

            let amountLine = lines[index + 1]
            guard let amount = parseCurrencyAmount(from: amountLine) else {
                index += 1
                continue
            }

            let currency = extractCurrencyCode(from: lines, start: index + 2) ?? "CAD"
            parsed.append(PayoutRecord(
                id: UUID().uuidString,
                timestamp: timestamp,
                amount: amount,
                currencyCode: currency.uppercased()
            ))

            index += 2
        }

        guard !parsed.isEmpty else {
            return "No payout rows detected. Paste rows in 'date/time + amount + currency' format."
        }

        payoutRecords = parsed.sorted { $0.timestamp < $1.timestamp }
        applyLatestPayoutCycle()
        return "Imported \(payoutRecords.count) payout records and applied the latest payout cycle."
    }

    func applyLatestPayoutCycle() {
        guard payoutRecords.count >= 2 else { return }
        let sorted = payoutRecords.sorted { $0.timestamp < $1.timestamp }
        let latest = sorted[sorted.count - 1]
        let previous = sorted[sorted.count - 2]
        lastPayoutDate = previous.timestamp
        payoutWindowEndDate = latest.timestamp
        payoutTotalSinceLast = latest.amount
    }

    // MARK: - Data Fetching

    func fetchAll() async {
        guard hasAPIKey else {
            errorMessage = "Please configure an ElevenLabs account and API key in Settings."
            return
        }
        guard !isLoading else { return }
        guard let apiKey = activeAPIKey() else { return }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            async let voicesTask = service.getVoices(apiKey: apiKey)
            async let userTask = service.getUser(apiKey: apiKey)

            let (fetchedVoices, fetchedUser) = try await (voicesTask, userTask)
            let sharedVoices = fetchedVoices.filter(\.isShared)
            let ownerID = resolveOwnerID(user: fetchedUser, sharedVoices: sharedVoices)

            let sharedMetrics: [SharedVoice]
            if let ownerID, !ownerID.isEmpty {
                sharedMetrics = (try? await service.getSharedVoices(ownerID: ownerID, apiKey: apiKey)) ?? []
            } else {
                sharedMetrics = []
            }

            let ownedSharedVoices = sharedVoices
                .filter { voice in
                    isOwnedSharedVoice(voice, for: fetchedUser, ownerID: ownerID)
                }
            let mergedVoices = mergeSharedMetrics(sharedMetrics, into: ownedSharedVoices)

            voices = mergedVoices.sorted { $0.name < $1.name }
            professionalVoices = voices.filter { $0.isProfessionalClone }
            sharedVoiceMetricsByVoiceID = makeSharedMetricsLookup(from: sharedMetrics, voices: voices)
            user = fetchedUser

            await fetchUsage(apiKey: apiKey)

            lastUpdated = Date()
            updateWindowTitle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchUsage(apiKey: String) async {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        let hourlyStart = calendar.date(byAdding: .hour, value: -24, to: now) ?? now
        let weekStart = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? now
        let monthStart = calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? now

        let allTimeStart = calendar.date(byAdding: .year, value: -3, to: now) ?? now

        do {
            async let hourlyTask = service.getUsage(start: hourlyStart, end: now, aggregation: "hour", apiKey: apiKey)
            async let weeklyTask = service.getUsage(start: weekStart, end: now, aggregation: "day", apiKey: apiKey)
            async let monthlyTask = service.getUsage(start: monthStart, end: now, aggregation: "day", apiKey: apiKey)
            async let allTimeTask = service.getUsage(start: allTimeStart, end: now, aggregation: "month", apiKey: apiKey)
            let payoutWindowStartRaw = min(lastPayoutDate, payoutWindowEndDate)
            let payoutWindowEndRaw = max(lastPayoutDate, payoutWindowEndDate)
            let payoutWindowStart = calendar.startOfDay(for: payoutWindowStartRaw)
            let payoutWindowEnd = calendar.date(
                byAdding: DateComponents(day: 1, second: -1),
                to: calendar.startOfDay(for: payoutWindowEndRaw)
            ) ?? payoutWindowEndRaw
            async let payoutWindowTask = service.getUsage(start: payoutWindowStart, end: payoutWindowEnd, aggregation: "day", apiKey: apiKey)

            let (hourly, weekly, monthly, allTime, payoutWindow) = try await (hourlyTask, weeklyTask, monthlyTask, allTimeTask, payoutWindowTask)
            let hourlyRequests = try? await service.getUsage(
                start: hourlyStart,
                end: now,
                aggregation: "hour",
                metric: "request_count",
                apiKey: apiKey
            )

            weeklyUsage = weekly
            monthlyUsage = monthly
            allTimeUsage = allTime
            payoutWindowUsage = payoutWindow

            mergeHourlyUsage(hourly, requestUsage: hourlyRequests)
            recomputeEarnings()
            recomputePayoutAllocation()
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
        return ElevenLabsService.makeBuckets(from: usage, voices: voices, ratePerThousand: ratePerThousand, customVoiceRates: effectiveVoiceRates(), voiceName: voiceName)
    }

    func monthlyBuckets(for voiceName: String? = nil) -> [EarningsBucket] {
        guard let usage = monthlyUsage else { return [] }
        return ElevenLabsService.makeBuckets(from: usage, voices: voices, ratePerThousand: ratePerThousand, customVoiceRates: effectiveVoiceRates(), voiceName: voiceName)
    }

    func customRate(for voice: Voice) -> Double? {
        customVoiceRates[voice.voiceId]
    }

    func ratePerThousandUsed(for voice: Voice) -> Double {
        if let custom = customVoiceRates[voice.voiceId], custom > 0 {
            return custom
        }
        if let calibrated = calibratedRate(for: voice) {
            return calibrated
        }
        return max(ratePerThousand, 0)
    }

    func rateSourceLabel(for voice: Voice) -> String {
        if customVoiceRates[voice.voiceId] != nil {
            return "Custom"
        }
        if calibratedRate(for: voice) != nil {
            return "Calibrated"
        }
        return "Global"
    }

    func recentHourlyBuckets(for voiceID: String? = nil) -> [HourlyVoiceBucket] {
        guard let voiceID else { return recentHourlyVoiceBuckets }
        return recentHourlyVoiceBuckets.filter { $0.voiceId == voiceID }
    }

    func setCustomRate(_ rate: Double?, for voice: Voice) {
        var updated = customVoiceRates
        if let rate, rate > 0 {
            updated[voice.voiceId] = rate
        } else {
            updated.removeValue(forKey: voice.voiceId)
        }
        customVoiceRates = updated
        recomputeEarnings()
    }

    // MARK: - Private Helpers

    private func activeAPIKey() -> String? {
        guard let accountID = selectedAccountID else { return nil }
        return KeychainService.load(for: accountID)
    }

    private func clearFetchedData() {
        voices = []
        professionalVoices = []
        user = nil
        weeklyUsage = nil
        monthlyUsage = nil
        allTimeUsage = nil
        payoutWindowUsage = nil
        weeklyEarnings = []
        monthlyEarnings = []
        allTimeEarnings = []
        payoutAllocatedEarnings = []
        sharedVoiceMetricsByVoiceID = [:]
        hourlyVoiceBuckets = []
        lastUpdated = nil
    }

    private func recomputeEarnings() {
        guard let weekly = weeklyUsage, let monthly = monthlyUsage, let allTime = allTimeUsage else { return }
        let effectiveRates = effectiveVoiceRates()

        let weeklyFromUsage = ElevenLabsService.computeEarnings(
            from: weekly,
            voices: voices,
            ratePerThousand: ratePerThousand,
            customVoiceRates: effectiveRates
        )
        let monthlyFromUsage = ElevenLabsService.computeEarnings(
            from: monthly,
            voices: voices,
            ratePerThousand: ratePerThousand,
            customVoiceRates: effectiveRates
        )
        let weeklyFromSharing = fallbackSharingEarnings(window: .week7d)
        let monthlyFromSharing = fallbackSharingEarnings(window: .month30d)

        weeklyEarnings = weeklyFromSharing.isEmpty ? weeklyFromUsage : weeklyFromSharing
        monthlyEarnings = monthlyFromSharing.isEmpty ? monthlyFromUsage : monthlyFromSharing
        allTimeEarnings = ElevenLabsService.computeEarnings(from: allTime, voices: voices, ratePerThousand: ratePerThousand, customVoiceRates: effectiveRates)
    }

    private func recomputePayoutAllocation() {
        guard let usage = payoutWindowUsage else {
            payoutAllocatedEarnings = []
            return
        }

        let baseVoices = professionalVoices.isEmpty ? voices : professionalVoices
        guard !baseVoices.isEmpty else {
            payoutAllocatedEarnings = []
            return
        }

        let totalsByVoice = ElevenLabsService.computeCharacterTotals(from: usage, voices: voices)
        let usageWindowDays = max(1.0, payoutWindowEndDate.timeIntervalSince(lastPayoutDate) / 86_400.0)
        let sharingWindow: SharingFallbackWindow = usageWindowDays <= 10 ? .week7d : .month30d

        var effectiveCharsByVoiceID: [String: Double] = [:]
        for voice in baseVoices {
            let usageChars = totalsByVoice[voice.voiceId]?.characters ?? 0
            let sharedChars = sharingCharacters(for: voice, window: sharingWindow)
            let effectiveChars = max(usageChars, sharedChars)
            effectiveCharsByVoiceID[voice.voiceId] = effectiveChars
        }

        let totalChars = effectiveCharsByVoiceID.values.reduce(0, +)

        payoutAllocatedEarnings = baseVoices
            .map { voice in
                let chars = effectiveCharsByVoiceID[voice.voiceId] ?? 0
                let share = totalChars > 0 ? (chars / totalChars) : 0
                let allocated = payoutTotalSinceLast > 0 ? (payoutTotalSinceLast * share) : 0
                return VoiceEarnings(
                    voice: voice,
                    characterCount: chars,
                    estimatedEarnings: allocated
                )
            }
            .sorted { $0.estimatedEarnings > $1.estimatedEarnings }
    }

    private func mergeHourlyUsage(_ usage: UsageResponse, requestUsage: UsageResponse? = nil) {
        let apiBuckets = ElevenLabsService.makeBuckets(
            from: usage,
            voices: voices,
            ratePerThousand: ratePerThousand,
            customVoiceRates: effectiveVoiceRates()
        )

        guard !apiBuckets.isEmpty else { return }

        let voiceLookup = Dictionary(uniqueKeysWithValues: voices.map { ($0.name, $0) })
        let requestCountsByBucketID = requestCountsByHourlyBucketID(from: requestUsage, voiceLookup: voiceLookup)
        let incoming = apiBuckets.compactMap { bucket -> HourlyVoiceBucket? in
            guard let voice = voiceLookup[bucket.voiceName] else { return nil }
            let bucketID = "\(voice.voiceId)-\(Int(bucket.date.timeIntervalSince1970))"
            return HourlyVoiceBucket(
                voiceId: voice.voiceId,
                voiceName: voice.name,
                timestamp: bucket.date,
                characters: bucket.characters,
                estimatedEarnings: bucket.earnings,
                requestCount: requestCountsByBucketID[bucketID]
            )
        }

        guard !incoming.isEmpty else { return }

        let cutoff = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        let merged = (hourlyVoiceBuckets + incoming)
            .filter { $0.timestamp >= cutoff }
            .reduce(into: [String: HourlyVoiceBucket]()) { result, bucket in
                if let existing = result[bucket.id] {
                    result[bucket.id] = mergeHourlyBucket(existing: existing, incoming: bucket)
                } else {
                    result[bucket.id] = bucket
                }
            }
            .values
            .sorted {
                if $0.timestamp == $1.timestamp {
                    return $0.voiceName < $1.voiceName
                }
                return $0.timestamp < $1.timestamp
            }

        hourlyVoiceBuckets = merged
        AppSettings.setHourlyVoiceBuckets(merged, for: selectedAccountID)
    }

    private func requestCountsByHourlyBucketID(
        from usage: UsageResponse?,
        voiceLookup: [String: Voice]
    ) -> [String: Double] {
        guard let usage else { return [:] }

        let requestBuckets = ElevenLabsService.makeBuckets(
            from: usage,
            voices: voices,
            ratePerThousand: 0
        )

        return requestBuckets.reduce(into: [String: Double]()) { result, bucket in
            guard let voice = voiceLookup[bucket.voiceName] else { return }
            let bucketID = "\(voice.voiceId)-\(Int(bucket.date.timeIntervalSince1970))"
            result[bucketID, default: 0] += bucket.characters
        }
    }

    private func mergeHourlyBucket(
        existing: HourlyVoiceBucket,
        incoming: HourlyVoiceBucket
    ) -> HourlyVoiceBucket {
        HourlyVoiceBucket(
            voiceId: incoming.voiceId,
            voiceName: incoming.voiceName,
            timestamp: incoming.timestamp,
            characters: incoming.characters,
            estimatedEarnings: incoming.estimatedEarnings,
            requestCount: incoming.requestCount ?? existing.requestCount
        )
    }

    private func migrateLegacyKeyIfNeeded() {
        if accounts.isEmpty, let legacyKey = KeychainService.loadLegacyIfPresent(), !legacyKey.isEmpty {
            let legacyAccount = ElevenLabsAccount(id: UUID().uuidString, name: "Primary Account")
            accounts = [legacyAccount]
            selectedAccountID = legacyAccount.id
            KeychainService.save(legacyKey, for: legacyAccount.id)
            KeychainService.deleteLegacy()
            hasCompletedOnboarding = true
        }
    }

    private func migrateLegacyDefaultRateIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "ratePerThousandChars"
        guard let stored = defaults.object(forKey: key) as? Double else {
            defaults.set(AppSettings.defaultRatePerThousand, forKey: key)
            return
        }

        if shouldReplaceStoredRate(stored) {
            defaults.set(AppSettings.defaultRatePerThousand, forKey: key)
        }
    }

    private func shouldReplaceStoredRate(_ rate: Double) -> Bool {
        rate <= 0 || rate > 0.02 || abs(rate - 0.03) < 0.0000001
    }

    private func customRatesStorageKey(for accountID: String?) -> String? {
        guard let accountID else { return nil }
        return "customVoiceRates_\(accountID)"
    }

    private func loadCustomRates(for accountID: String?) -> [String: Double] {
        guard let storageKey = customRatesStorageKey(for: accountID),
              let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func loadAndNormalizeCustomRates(for accountID: String?) -> [String: Double] {
        let stored = loadCustomRates(for: accountID)
        let normalized = stored.filter { _, rate in
            !shouldReplaceStoredRate(rate) && abs(rate - AppSettings.defaultRatePerThousand) > 0.0000001
        }
        if normalized.count != stored.count {
            persistCustomRates(normalized, for: accountID)
        }
        return normalized
    }

    private func persistCustomRates(_ rates: [String: Double], for accountID: String?) {
        guard let storageKey = customRatesStorageKey(for: accountID) else { return }
        if let encoded = try? JSONEncoder().encode(rates) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func deleteCustomRates(for accountID: String) {
        UserDefaults.standard.removeObject(forKey: "customVoiceRates_\(accountID)")
    }

    private enum SharingFallbackWindow {
        case week7d
        case month30d
    }

    private func fallbackSharingEarnings(window: SharingFallbackWindow) -> [VoiceEarnings] {
        let baseVoices = professionalVoices.isEmpty ? voices : professionalVoices
        return baseVoices.map { voice in
            let chars = sharingCharacters(for: voice, window: window)
            let earnings = chars * (effectiveRate(for: voice) / 1000.0)

            return VoiceEarnings(
                voice: voice,
                characterCount: chars,
                estimatedEarnings: earnings
            )
        }
        .sorted { $0.estimatedEarnings > $1.estimatedEarnings }
    }

    private func resolveOwnerID(user: UserResponse, sharedVoices: [Voice]) -> String? {
        if let userID = user.publicUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userID.isEmpty {
            return userID
        }
        if let ownerID = sharedVoices
            .compactMap({ $0.sharing?.publicOwnerID?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return ownerID
        }
        return nil
    }

    private func isOwnedSharedVoice(_ voice: Voice, for user: UserResponse, ownerID: String?) -> Bool {
        let ownerId = voice.sharing?.publicOwnerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userId = user.publicUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedOwner = ownerID?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let ownerId, !ownerId.isEmpty, let userId, !userId.isEmpty {
            return ownerId == userId
        }
        if let ownerId, !ownerId.isEmpty, let resolvedOwner, !resolvedOwner.isEmpty {
            return ownerId == resolvedOwner
        }
        return true
    }

    private func mergeSharedMetrics(_ metrics: [SharedVoice], into voices: [Voice]) -> [Voice] {
        guard !metrics.isEmpty else { return voices }

        let byVoiceID = metrics.reduce(into: [String: SharedVoice]()) { result, metric in
            if result[metric.voiceId] == nil {
                result[metric.voiceId] = metric
            }
        }
        let byNormalizedName = metrics.reduce(into: [String: SharedVoice]()) { result, metric in
            let key = normalizedKey(metric.name)
            if result[key] == nil {
                result[key] = metric
            }
        }

        return voices.map { voice in
            let originalID = voice.sharing?.originalVoiceId
            let sharedMetric = byVoiceID[voice.voiceId]
                ?? (originalID.flatMap { byVoiceID[$0] })
                ?? byNormalizedName[normalizedKey(voice.name)]

            guard let sharedMetric else { return voice }
            let sharing = mergedSharing(base: voice.sharing, metric: sharedMetric)
            return Voice(
                voiceId: voice.voiceId,
                name: voice.name,
                category: voice.category,
                sharing: sharing,
                labels: voice.labels
            )
        }
    }

    private func makeSharedMetricsLookup(from metrics: [SharedVoice], voices: [Voice]) -> [String: SharedVoice] {
        guard !metrics.isEmpty else { return [:] }

        let byVoiceID = metrics.reduce(into: [String: SharedVoice]()) { result, metric in
            if result[metric.voiceId] == nil {
                result[metric.voiceId] = metric
            }
        }
        let byNormalizedName = metrics.reduce(into: [String: SharedVoice]()) { result, metric in
            let key = normalizedKey(metric.name)
            if result[key] == nil {
                result[key] = metric
            }
        }

        var lookup: [String: SharedVoice] = [:]
        for voice in voices {
            let originalID = voice.sharing?.originalVoiceId
            let metric = byVoiceID[voice.voiceId]
                ?? (originalID.flatMap { byVoiceID[$0] })
                ?? byNormalizedName[normalizedKey(voice.name)]
            if let metric {
                lookup[voice.voiceId] = metric
            }
        }
        return lookup
    }

    private func effectiveRate(for voice: Voice) -> Double {
        ratePerThousandUsed(for: voice)
    }

    private func effectiveVoiceRates() -> [String: Double] {
        voices.reduce(into: [:]) { result, voice in
            result[voice.voiceId] = ratePerThousandUsed(for: voice)
        }
    }

    private func calibratedRate(for voice: Voice) -> Double? {
        let key = normalizedKey(voice.name)

        if key.contains("knoxdark") {
            return 0.01005328
        }
        if key.contains("austinknoxv3") || key.contains("goodoltexas") {
            return 0.01336976
        }
        if key.contains("brodude") || key.contains("gymfeels") {
            return 0.01301101
        }

        return nil
    }

    private func sharingCharacters(for voice: Voice, window: SharingFallbackWindow) -> Double {
        let metric = sharedVoiceMetricsByVoiceID[voice.voiceId]
        switch window {
        case .week7d:
            return max(
                voice.sharing?.usageCharacterCount7d ?? 0,
                metric?.usageCharacterCount7d ?? 0
            )
        case .month30d:
            let yearly = max(
                voice.sharing?.usageCharacterCount1y ?? 0,
                metric?.usageCharacterCount1y ?? 0
            )
            return yearly > 0 ? (yearly * (30.0 / 365.0)) : 0
        }
    }

    private func mergedSharing(base: VoiceSharing?, metric: SharedVoice) -> VoiceSharing {
        VoiceSharing(
            status: base?.status ?? "enabled",
            rate: base?.rate ?? metric.rate,
            likedByCount: base?.likedByCount,
            clonedByCount: metric.clonedByCount ?? base?.clonedByCount,
            usageCharacterCount7d: metric.usageCharacterCount7d ?? base?.usageCharacterCount7d,
            usageCharacterCount1y: metric.usageCharacterCount1y ?? base?.usageCharacterCount1y,
            historyCostTokens: base?.historyCostTokens,
            originalVoiceId: base?.originalVoiceId,
            publicOwnerID: base?.publicOwnerID ?? metric.publicOwnerID,
            name: base?.name ?? metric.name
        )
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func parseCurrencyAmount(from line: String) -> Double? {
        let allowed = CharacterSet(charactersIn: "0123456789.,")
        let filtered = line.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        let normalized = filtered.replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    private func extractCurrencyCode(from lines: [String], start: Int) -> String? {
        guard start < lines.count else { return nil }
        for idx in start..<min(start + 3, lines.count) {
            let candidate = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count == 3, candidate.range(of: "^[A-Za-z]{3}$", options: .regularExpression) != nil {
                return candidate
            }
        }
        return nil
    }
}
