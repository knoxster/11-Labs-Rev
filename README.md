# ElevenLabs Payout Dashboard

A native macOS SwiftUI app that displays your ElevenLabs Voice Library earnings in the menu bar, title bar, and a full dashboard window.

Current release: **0.0.2.1**. See `RELEASE_NOTES.md` for details.

## Requirements
- macOS 13.0 (Ventura) or later
- Xcode 15+
- ElevenLabs API key (Creator plan or above for professional voice clones)

## Project Setup in Xcode

1. Open Xcode → File → New → Project
2. Choose **macOS → App**
3. Product Name: `ElevenLabsDashboard`
4. Interface: **SwiftUI**, Language: **Swift**
5. Uncheck "Include Tests"
6. Replace all generated files with the files in this project

## Entitlements Required

In your `.entitlements` file, ensure you have:
```xml
<key>com.apple.security.network.client</key>
<true/>
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.yourname.ElevenLabsDashboard</string>
</array>
```

## File Structure

```
ElevenLabsDashboard/
├── ElevenLabsDashboardApp.swift      ← App entry point + MenuBarExtra
├── Models/
│   ├── Models.swift                  ← All data models
├── Services/
│   ├── ElevenLabsService.swift       ← API client
│   └── KeychainService.swift         ← Secure API key storage
├── ViewModels/
│   └── AppViewModel.swift            ← Central state + polling logic
└── Views/
    ├── ContentView.swift             ← Main tabbed window
    ├── DashboardView.swift           ← Overview + payout hero display
    ├── EarningsByVoiceView.swift     ← Weekly/monthly voice breakdown
    ├── HourlyBucketsView.swift       ← Last-24-hours hourly buckets by voice
    ├── VoiceComparisonView.swift     ← Side-by-side voice revenue chart
    └── SettingsView.swift            ← API key, rate, polling config
```

## ⚠️ API Limitation Note

ElevenLabs does **not** expose Voice Library payout balance or earnings-from-others via their public REST API. Payouts flow through Stripe Connect.

The app handles this in two ways:
1. **Estimated Earnings** — Calculated from characters used × your configured rate per 1,000 characters (set in Settings)
2. **Manual Balance Entry** — Enter your known pending Stripe balance manually; the app keeps it displayed in the title bar and menu bar

The app uses these official public endpoints:
- `GET /v1/voices` — your professional voice clones + sharing metadata
- `GET /v1/usage/character-stats` — character usage broken down by voice (weekly/monthly)
- `GET /v1/user` — account info

## First-Run Setup

On first launch, the app opens a setup flow that asks for:
- Account name
- ElevenLabs API key
- Default payout rate per 1,000 characters
- Auto-refresh interval
- Weekly/monthly lookback windows

The app stores account metadata in `UserDefaults` and API keys securely in Keychain.

## Multi-Account Support

- Supports up to **5** ElevenLabs accounts
- Each account has its own API key and saved voice-specific custom rates
- You can switch the active account in Settings

## Getting Your API Key

1. Log in to [elevenlabs.io](https://elevenlabs.io)
2. Click **Developers** in the left sidebar
3. Select the **API Keys** tab
4. Create or copy your key
5. Paste it into first-run setup or Settings within the app

## Finding Your Payout Rate

1. Go to [elevenlabs.io](https://elevenlabs.io) → My Voices
2. Click **View** on your Professional Voice Clone
3. Click the sharing icon → **Sharing Options**
4. Your rate (per 1,000 characters) is shown there
5. Enter this rate in Settings → Payout Rate
