// ElevenLabsService.swift
// ElevenLabsDashboard
//
// Handles all calls to the ElevenLabs REST API.
// Base URL: https://api.elevenlabs.io
// Auth:     xi-api-key header

import Foundation

enum ELError: LocalizedError {
    case noAPIKey
    case invalidResponse(Int, String?)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your ElevenLabs API key in Settings."
        case .invalidResponse(let code, let details):
            if let details, !details.isEmpty {
                return "API returned HTTP \(code): \(details)"
            }
            return "API returned HTTP \(code). Check your API key and plan."
        case .decodingError(let msg):
            return "Could not parse API response: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}

actor ElevenLabsService {

    private let baseURL = URL(string: "https://api.elevenlabs.io")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth Header

    private func request(path: String, queryItems: [URLQueryItem] = [], apiKey: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var req = URLRequest(url: components.url!)
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func fetch<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ELError.networkError("No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ELError.invalidResponse(http.statusCode, message)
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ELError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Voices

    /// Returns all voices in the user's library.
    /// Professional clones are filtered by `category == "professional"`.
    func getVoices(apiKey: String) async throws -> [Voice] {
        guard !apiKey.isEmpty else { throw ELError.noAPIKey }
        let req = request(path: "/v1/voices", apiKey: apiKey)
        let response = try await fetch(VoiceListResponse.self, request: req)
        return response.voices
    }

    // MARK: - User

    func getUser(apiKey: String) async throws -> UserResponse {
        guard !apiKey.isEmpty else { throw ELError.noAPIKey }
        let req = request(path: "/v1/user", apiKey: apiKey)
        return try await fetch(UserResponse.self, request: req)
    }

    // MARK: - Shared Voices

    func getSharedVoices(ownerID: String, apiKey: String) async throws -> [SharedVoice] {
        guard !apiKey.isEmpty else { throw ELError.noAPIKey }
        guard !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "owner_id", value: ownerID),
            URLQueryItem(name: "page_size", value: "100")
        ]
        let req = request(path: "/v1/shared-voices", queryItems: queryItems, apiKey: apiKey)
        do {
            let response = try await fetch(SharedVoiceListResponse.self, request: req)
            return response.voices
        } catch {
            return []
        }
    }

    // MARK: - Usage (character stats by voice)

    /// Fetches character usage broken down by voice name.
    ///
    /// - Parameters:
    ///   - start: Start of window
    ///   - end: End of window
    ///   - aggregation: "hour" | "day" | "week" | "month" | "cumulative"
    ///   - apiKey: ElevenLabs API key
    func getUsage(
        start: Date,
        end: Date,
        aggregation: String,
        metric: String? = nil,
        apiKey: String
    ) async throws -> UsageResponse {
        guard !apiKey.isEmpty else { throw ELError.noAPIKey }

        // Timestamps in milliseconds
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs   = Int64(end.timeIntervalSince1970 * 1000)

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "start_unix", value: "\(startMs)"),
            URLQueryItem(name: "end_unix",   value: "\(endMs)"),
            URLQueryItem(name: "aggregation_interval", value: aggregation),
            URLQueryItem(name: "breakdown_type", value: "voice")
        ]
        if let metric, !metric.isEmpty {
            queryItems.append(URLQueryItem(name: "metric", value: metric))
        }

        let req = request(path: "/v1/usage/character-stats",
                          queryItems: queryItems,
                          apiKey: apiKey)
        return try await fetch(UsageResponse.self, request: req)
    }

    /// Convenience: cumulative totals over a window (no breakdown)
    func getTotalUsage(start: Date, end: Date, apiKey: String) async throws -> UsageResponse {
        guard !apiKey.isEmpty else { throw ELError.noAPIKey }

        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs   = Int64(end.timeIntervalSince1970 * 1000)

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "start_unix", value: "\(startMs)"),
            URLQueryItem(name: "end_unix",   value: "\(endMs)"),
            URLQueryItem(name: "aggregation_interval", value: "cumulative"),
            URLQueryItem(name: "breakdown_type", value: "voice")
        ]
        let req = request(path: "/v1/usage/character-stats",
                          queryItems: queryItems,
                          apiKey: apiKey)
        return try await fetch(UsageResponse.self, request: req)
    }
}

// MARK: - Earnings Calculation

extension ElevenLabsService {

    /// Converts a UsageResponse into per-voice VoiceEarnings for a given period.
    /// earnings = totalChars × (ratePerThousand / 1000)
    static func computeEarnings(
        from usage: UsageResponse,
        voices: [Voice],
        ratePerThousand: Double,
        customVoiceRates: [String: Double] = [:]
    ) -> [VoiceEarnings] {
        let voiceByName = voiceLookupByName(voices: voices)
        let voiceById = voiceLookupById(voices: voices)

        var results: [VoiceEarnings] = []

        for (usageKey, buckets) in usage.usage {
            guard usageKey != "All" else { continue }
            guard let voice = resolveVoice(for: usageKey, byId: voiceById, byName: voiceByName),
                  voice.isShared else { continue }

            let totalChars = buckets.reduce(0, +)
            guard totalChars > 0 else { continue }

            // Use voice-specific rate if available, else global setting
            let rate: Double
            if let customRate = customVoiceRates[voice.voiceId],
               customRate > 0 {
                rate = customRate
            } else {
                rate = ratePerThousand
            }

            let earnings = totalChars * (rate / 1000.0)

            results.append(VoiceEarnings(
                voice: voice,
                characterCount: totalChars,
                estimatedEarnings: earnings
            ))
        }

        return results.sorted { $0.estimatedEarnings > $1.estimatedEarnings }
    }

    /// Converts usage buckets into EarningsBucket array for charting
    static func makeBuckets(
        from usage: UsageResponse,
        voices: [Voice],
        ratePerThousand: Double,
        customVoiceRates: [String: Double] = [:],
        voiceName: String? = nil
    ) -> [EarningsBucket] {
        let voiceByName = voiceLookupByName(voices: voices)
        let voiceById = voiceLookupById(voices: voices)
        var buckets: [EarningsBucket] = []

        for (usageKey, values) in usage.usage {
            guard usageKey != "All" else { continue }
            guard let voice = resolveVoice(for: usageKey, byId: voiceById, byName: voiceByName),
                  voice.isShared else { continue }
            if let filter = voiceName, voice.name != filter { continue }

            for (i, chars) in values.enumerated() {
                guard i < usage.time.count else { continue }
                let date = usage.time[i].asDate
                let rate: Double
                if let customRate = customVoiceRates[voice.voiceId],
                   customRate > 0 {
                    rate = customRate
                } else {
                    rate = ratePerThousand
                }
                let earnings = chars * (rate / 1000.0)
                buckets.append(EarningsBucket(
                    date: date,
                    voiceName: voice.name,
                    characters: chars,
                    earnings: earnings
                ))
            }
        }

        return buckets.sorted { $0.date < $1.date }
    }

    static func computeCharacterTotals(
        from usage: UsageResponse,
        voices: [Voice]
    ) -> [String: (voice: Voice, characters: Double)] {
        let voiceByName = voiceLookupByName(voices: voices)
        let voiceById = voiceLookupById(voices: voices)
        var totals: [String: (voice: Voice, characters: Double)] = [:]

        for (usageKey, buckets) in usage.usage {
            guard usageKey != "All" else { continue }
            guard let voice = resolveVoice(for: usageKey, byId: voiceById, byName: voiceByName),
                  voice.isShared else { continue }
            let chars = buckets.reduce(0, +)
            guard chars > 0 else { continue }
            let current = totals[voice.voiceId]?.characters ?? 0
            totals[voice.voiceId] = (voice: voice, characters: current + chars)
        }

        return totals
    }

    private static func voiceLookupByName(voices: [Voice]) -> [String: Voice] {
        voices.reduce(into: [:]) { result, voice in
            let aliases = [
                voice.name,
                voice.sharing?.name,
                voice.labels?["name"]
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

            for alias in aliases where !alias.isEmpty {
                insertLookup(alias, voice: voice, into: &result)
            }
        }
    }

    private static func voiceLookupById(voices: [Voice]) -> [String: Voice] {
        voices.reduce(into: [:]) { result, voice in
            result[voice.voiceId] = voice
            if let originalVoiceId = voice.sharing?.originalVoiceId,
               !originalVoiceId.isEmpty {
                result[originalVoiceId] = voice
            }
        }
    }

    private static func resolveVoice(
        for usageKey: String,
        byId: [String: Voice],
        byName: [String: Voice]
    ) -> Voice? {
        let rawKey = usageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawKey.isEmpty else { return nil }
        let lowerKey = rawKey.lowercased()
        let normalizedKey = normalizedMatchKey(rawKey)

        if let byExactId = byId[rawKey] {
            return byExactId
        }
        if let byExactName = byName[rawKey] {
            return byExactName
        }
        if let byLowerName = byName[lowerKey] {
            return byLowerName
        }
        if let byNormalizedName = byName[normalizedKey] {
            return byNormalizedName
        }
        if let byContainedId = byId.first(where: { rawKey.contains($0.key) || $0.key.contains(rawKey) })?.value {
            return byContainedId
        }
        if let byContainedName = byName.first(where: { key, _ in key.contains(lowerKey) || lowerKey.contains(key) })?.value {
            return byContainedName
        }
        if let byContainedNormalized = byName.first(where: { key, _ in key.contains(normalizedKey) || normalizedKey.contains(key) })?.value {
            return byContainedNormalized
        }
        return nil
    }

    private static func insertLookup(_ raw: String, voice: Voice, into map: inout [String: Voice]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let keys = [
            trimmed,
            trimmed.lowercased(),
            normalizedMatchKey(trimmed)
        ]

        for key in keys where !key.isEmpty {
            if map[key] == nil {
                map[key] = voice
            }
        }
    }

    private static func normalizedMatchKey(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}
