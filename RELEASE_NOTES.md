# Release Notes — 0.0.2.1

This release is focused on ElevenLabs Voice Library creators who need a practical way to track the revenue their shared professional voices generate.

## Highlights

- Adds a native macOS dashboard for tracking shared voice revenue estimates by voice.
- Supports up to 5 ElevenLabs accounts, each with its own stored API key and settings.
- Filters the dashboard to your shared professional voice clones instead of general marketplace voices.
- Uses voice-specific calibrated payout rates where available, with custom per-voice overrides still supported.
- Adds payout import support so creators can paste payout rows and see a last-31-days payout total.

## Voice Revenue Tracking

- Shows weekly, monthly, all-time, and since-last-payout views for shared voices.
- Breaks down estimated earnings by voice using character usage and each voice’s effective rate.
- Allocates payout-period totals across voices by each voice’s usage share when exact per-voice payout data is not available from ElevenLabs.
- Keeps Stripe/payout figures separate from usage estimates so imported payout totals do not distort character-based charts.

## Hourly Buckets

- Saves per-voice hourly character buckets locally for the last 31 days.
- Adds a new 24 Hours view for looking at the most recent day one hour at a time by voice.
- Adds request-count tracking from `GET /v1/usage/character-stats` using `metric=request_count`.
- Shows hourly chart options for earnings, characters, and requests.

## Setup and Storage

- Adds first-run setup for account name, API key, default payout rate, refresh interval, and usage windows.
- Stores API keys in macOS Keychain.
- Stores local preferences, payout rows, custom rates, and hourly usage buckets per account.

## Notes

- ElevenLabs does not currently expose exact payout-period revenue by voice through the public API.
- This app estimates voice-level revenue from character usage, request-count metrics, calibrated rates, and user-provided payout data.
- Stripe and ElevenLabs payout pages remain the source of truth for finalized payout totals.
