// Models.swift
// ElevenLabsDashboard
//
// All data models used across the app.

import Foundation

// MARK: - Voice Models

struct VoiceListResponse: Codable {
    let voices: [Voice]
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
    let historyCostTokens: Int?
    let originalVoiceId: String?
    let publicOwnerID: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case status, rate
        case likedByCount = "liked_by_count"
        case clonedByCount = "cloned_by_count"
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

    enum CodingKeys: String, CodingKey {
        case subscriptionTier = "xi_api_tier"
        case characterCount = "character_count"
        case characterLimit = "character_limit"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
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
    static let defaultRatePerThousand: Double = 0.03    // $0.03 per 1k chars (base EL rate)

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
