// Models.swift
// ElevenLabsDashboard
//
// All data models used across the app.

import Foundation

// MARK: - Voice Models

struct VoiceListResponse: Codable {
    let voices: [Voice]
}

struct SharedVoiceListResponse: Codable {
    let voices: [SharedVoice]
}

struct SharedVoice: Codable, Hashable {
    let publicOwnerID: String?
    let voiceId: String
    let name: String
    let clonedByCount: Int?
    let usageCharacterCount7d: Double?
    let usageCharacterCount1y: Double?
    let rate: Double?

    enum CodingKeys: String, CodingKey {
        case publicOwnerID = "public_owner_id"
        case voiceId = "voice_id"
        case name
        case clonedByCount = "cloned_by_count"
        case usageCharacterCount7d = "usage_character_count_7d"
        case usageCharacterCount1y = "usage_character_count_1y"
        case rate
    }
}

struct ElevenLabsAccount: Identifiable, Codable, Hashable {
    let id: String
    var name: String
}

struct PayoutRecord: Identifiable, Codable, Hashable {
    let id: String
    let timestamp: Date
    let amount: Double
    let currencyCode: String
}

struct HourlyVoiceBucket: Identifiable, Codable, Hashable {
    let voiceId: String
    let voiceName: String
    let timestamp: Date
    let characters: Double
    let estimatedEarnings: Double
    let requestCount: Double?

    var id: String { "\(voiceId)-\(Int(timestamp.timeIntervalSince1970))" }
}

struct Voice: Identifiable, Codable, Hashable {
    let voiceId: String
    let name: String
    let category: String?
    let sharing: VoiceSharing?
    let labels: [String: String]?

    var id: String { voiceId }

    var isProfessionalClone: Bool {
        category == "professional"
    }

    var isShared: Bool {
        sharing?.status == "enabled"
    }

    /// Rate in dollars per 1,000 characters (from sharing settings).
    /// ElevenLabs doesn't always expose this in the API response,
    /// so the user configures a fallback global rate in Settings.
    var sharingRate: Double? {
        sharing?.rate
    }

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name, category, sharing, labels
    }
}

struct VoiceSharing: Codable, Hashable {
    let status: String?
    let rate: Double?
    let likedByCount: Int?
    let clonedByCount: Int?
    let usageCharacterCount7d: Double?
    let usageCharacterCount1y: Double?
    let historyCostTokens: Int?
    let originalVoiceId: String?
    let publicOwnerID: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case status, rate
        case likedByCount = "liked_by_count"
        case clonedByCount = "cloned_by_count"
        case usageCharacterCount7d = "usage_character_count_7d"
        case usageCharacterCount1y = "usage_character_count_1y"
        case historyCostTokens = "history_cost_tokens"
        case originalVoiceId = "original_voice_id"
        case publicOwnerID = "public_owner_id"
        case name
    }
}

// MARK: - Usage Models

struct UsageResponse: Codable {
    /// Unix timestamps in milliseconds for each bucket
    let time: [Int64]
    /// Map from voice name (or "All") → array of character counts per bucket
    let usage: [String: [Double]]
}

// MARK: - User Model

struct UserResponse: Codable {
    let subscriptionTier: String?
    let characterCount: Int?
    let characterLimit: Int?
    let firstName: String?
    let lastName: String?
    let email: String?
    let publicUserID: String?

    enum CodingKeys: String, CodingKey {
        case subscriptionTier = "xi_api_tier"
        case characterCount = "character_count"
        case characterLimit = "character_limit"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case publicUserID = "public_user_id"
    }
}

// MARK: - Derived / App Models

/// A single voice's earnings for a given time period
struct VoiceEarnings: Identifiable {
    let voice: Voice
    let characterCount: Double
    let estimatedEarnings: Double
    var id: String { voice.voiceId }
}

/// A time-bucketed data point for charts
struct EarningsBucket: Identifiable {
    let date: Date
    let voiceName: String
    let characters: Double
    let earnings: Double
    var id: String { "\(voiceName)-\(date.timeIntervalSince1970)" }
}

/// The period selector for earnings views
enum EarningsPeriod: String, CaseIterable {
    case week = "Weekly"
    case month = "Monthly"
}

// MARK: - Settings

struct AppSettings {
    static let defaultPollingInterval: Double = 15 * 60 // 15 minutes
    static let defaultRatePerThousand: Double = 0.00801037 // Knox Dark 12-month effective USD rate per 1k chars

    static var pollingInterval: Double {
        get { UserDefaults.standard.double(forKey: "pollingInterval").nonZero ?? defaultPollingInterval }
        set { UserDefaults.standard.set(newValue, forKey: "pollingInterval") }
    }

    static var ratePerThousandChars: Double {
        get { UserDefaults.standard.double(forKey: "ratePerThousandChars").nonZero ?? defaultRatePerThousand }
        set { UserDefaults.standard.set(newValue, forKey: "ratePerThousandChars") }
    }

    /// Manually-entered pending Stripe balance (since EL doesn't expose this via API)
    static var manualPendingBalance: Double {
        get { UserDefaults.standard.double(forKey: "manualPendingBalance") }
        set { UserDefaults.standard.set(newValue, forKey: "manualPendingBalance") }
    }

    static var lookbackWeeks: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "lookbackWeeks")
            return v == 0 ? 12 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "lookbackWeeks") }
    }

    static var lookbackMonths: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "lookbackMonths")
            return v == 0 ? 12 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "lookbackMonths") }
    }

    static var lastPayoutDate: Date {
        get {
            if let stored = UserDefaults.standard.object(forKey: "lastPayoutDate") as? Date {
                return stored
            }
            return Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        }
        set { UserDefaults.standard.set(newValue, forKey: "lastPayoutDate") }
    }

    static var payoutTotalSinceLast: Double {
        get { UserDefaults.standard.double(forKey: "payoutTotalSinceLast") }
        set { UserDefaults.standard.set(newValue, forKey: "payoutTotalSinceLast") }
    }

    static var payoutWindowEndDate: Date {
        get {
            if let stored = UserDefaults.standard.object(forKey: "payoutWindowEndDate") as? Date {
                return stored
            }
            return Date()
        }
        set { UserDefaults.standard.set(newValue, forKey: "payoutWindowEndDate") }
    }

    static var elevenLabsAccounts: [ElevenLabsAccount] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "elevenLabsAccounts"),
                  let decoded = try? JSONDecoder().decode([ElevenLabsAccount].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: "elevenLabsAccounts")
            }
        }
    }

    static var selectedAccountID: String? {
        get { UserDefaults.standard.string(forKey: "selectedAccountID") }
        set { UserDefaults.standard.set(newValue, forKey: "selectedAccountID") }
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    static var importedPayoutRecords: [PayoutRecord] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "importedPayoutRecords"),
                  let decoded = try? JSONDecoder().decode([PayoutRecord].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: "importedPayoutRecords")
            }
        }
    }

    static func hourlyVoiceBuckets(for accountID: String?) -> [HourlyVoiceBucket] {
        guard let accountID,
              let data = UserDefaults.standard.data(forKey: hourlyVoiceBucketsKey(for: accountID)),
              let decoded = try? JSONDecoder().decode([HourlyVoiceBucket].self, from: data) else {
            return []
        }
        return decoded
    }

    static func setHourlyVoiceBuckets(_ buckets: [HourlyVoiceBucket], for accountID: String?) {
        guard let accountID else { return }
        if let encoded = try? JSONEncoder().encode(buckets) {
            UserDefaults.standard.set(encoded, forKey: hourlyVoiceBucketsKey(for: accountID))
        }
    }

    private static func hourlyVoiceBucketsKey(for accountID: String) -> String {
        "hourlyVoiceBuckets_\(accountID)"
    }

}

// MARK: - Helpers

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }

    func asFormattedEarnings() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }
}

extension Int64 {
    var asDate: Date {
        Date(timeIntervalSince1970: Double(self) / 1000.0)
    }
}

extension PayoutRecord {
    func formattedAmount() -> String {
        amount.asFormattedCurrency(currencyCode)
    }
}

extension Double {
    func asFormattedCurrency(_ currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "\(currencyCode) \(String(format: "%.2f", self))"
    }
}
