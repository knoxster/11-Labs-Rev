// ElevenLabsService.swift
// ElevenLabsDashboard
//
// Handles all calls to the ElevenLabs REST API.
// Base URL: https://api.elevenlabs.io
// Auth:     xi-api-key header

import Foundation

enum ELError: LocalizedError {
    case noAPIKey
    case invalidResponse(Int)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your ElevenLabs API key in Settings."
        case .invalidResponse(let code):
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
            throw ELError.invalidResponse(http.statusCode)
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
        apiKey: String
    ) async throws -> UsageResponse {
        guard !apiKey.isEmpty else { throw ELError.noAPIKey }

        // Timestamps in milliseconds
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs   = Int64(end.timeIntervalSince1970 * 1000)

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "start_unix", value: "\(startMs)"),
            URLQueryItem(name: "end_unix",   value: "\(endMs)"),
            URLQueryItem(name: "aggregation_interval", value: aggregation),
            URLQueryItem(name: "breakdown_type", value: "voice"),
            URLQueryItem(name: "metric", value: "characters")
        ]

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
            URLQueryItem(name: "breakdown_type", value: "voice"),
            URLQueryItem(name: "metric", value: "characters")
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
        ratePerThousand: Double
    ) -> [VoiceEarnings] {
        // Build a lookup by voice name
        let voiceByName = Dictionary(uniqueKeysWithValues: voices.map { ($0.name, $0) })

        var results: [VoiceEarnings] = []

        for (voiceName, buckets) in usage.usage {
            guard voiceName != "All" else { continue }

            let totalChars = buckets.reduce(0, +)
            guard totalChars > 0 else { continue }

            // Use voice-specific rate if available, else global setting
            let rate: Double
            if let voice = voiceByName[voiceName],
               let vRate = voice.sharingRate, vRate > 0 {
                rate = vRate
            } else {
                rate = ratePerThousand
            }

            let earnings = totalChars * (rate / 1000.0)

            // Match to a Voice object (or create a placeholder)
            let voice = voiceByName[voiceName] ?? Voice(
                voiceId: UUID().uuidString,
                name: voiceName,
                category: nil,
                sharing: nil,
                labels: nil
            )

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
        ratePerThousand: Double,
        voiceName: String? = nil
    ) -> [EarningsBucket] {
        var buckets: [EarningsBucket] = []

        for (name, values) in usage.usage {
            guard name != "All" else { continue }
            if let filter = voiceName, name != filter { continue }

            for (i, chars) in values.enumerated() {
                guard i < usage.time.count else { continue }
                let date = usage.time[i].asDate
                let earnings = chars * (ratePerThousand / 1000.0)
                buckets.append(EarningsBucket(
                    date: date,
                    voiceName: name,
                    characters: chars,
                    earnings: earnings
                ))
            }
        }

        return buckets.sorted { $0.date < $1.date }
    }
}
