# Camo Track on Google Play: what to enter where

Package name: `app.camotrack.android` (permanent once the first build is uploaded).
Store listing text: `fastlane/metadata/android/<locale>/` (title, short and full
description, changelogs), in fastlane's layout so `fastlane supply` can upload it.

## Create app
- App name: Camo Track · Default language: English (United Kingdom) · App · Free
- Declarations: Developer Program Policies, US export laws: tick both.

## Store settings
- Category: **Tools** (Play has no Reference category for apps; Tools is the
  nearest to iOS's Reference/Utilities). Tags: pick "Tracker" / "Guide" style tags offered.
- Contact email: support@camo-track.app · Website: https://camo-track.app
- Phone: leave empty (optional).

## App content
- **Privacy policy**: https://camo-track.app/privacy-policy (has the Android
  sections from 2026-11-17; publish the camo-track-site commit first).
- **App access**: All functionality is available without special access. (No
  login. Premium can be tested with Play's licence testers.)
- **Ads**: Yes, the app contains ads.
- **Content rating** (IARC questionnaire): category "Reference, News, or
  Educational". Violence: no (the app shows pictures of game weapons and camo
  textures, no violence or gore). Sexuality, language, controlled substances,
  gambling: no. User interaction: users can't communicate or share content with
  each other in the app (sharing a progress card goes through Android's share
  sheet to other apps); no location sharing; digital purchases: yes. Expect
  roughly PEGI 3 / Everyone.
- **Target audience**: 13–15, 16–17, 18+ (the privacy policy doesn't address
  under-13s). Not designed for children.
- **News app**: No. **COVID-19**: No. **Government app**: No. **Financial
  features**: none. **Health**: none.
- **Advertising ID**: Yes, used for **Advertising or marketing** (the LevelPlay
  SDK declares `AD_ID`).
- **Data safety** (below).

## Data safety
Encrypted in transit: **Yes**. Users can request deletion: **Yes** (email
support@camo-track.app; progress itself never leaves the phone except Android's
own backup, which is Google's).

Collected and shared, all by the ads SDK (Unity LevelPlay / Unity Ads), only
for free players, for **Advertising or marketing** (and Analytics / Fraud
prevention as the SDK states):
| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Location → Approximate location (from the IP address) | Yes | Yes | No | Advertising, Fraud prevention |
| App activity → App interactions (ad views/taps) | Yes | Yes | No | Advertising, Analytics |
| App info and performance → Diagnostics | Yes | Yes | No | Analytics |
| Device or other IDs (advertising ID, app set ID) | Yes | Yes | No | Advertising, Fraud prevention |

Collected by the app itself (not shared):
| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| App activity → Other user-generated content (stream overlay figures and the channel name, only while the overlay is on) | Yes | No | Yes | App functionality |

Not collected: name, email, contacts, photos (stash photos are read on the
device), payment info (Google Play handles purchases), messages, files, health,
precise location, web history. Support emails are sent by the user from their
own mail app.

Check Unity's current "Google Play Data safety" guidance for LevelPlay and
Unity Ads before submitting, in case its list has changed.

## Monetize
- In-app products → One-time: `premium_lifetime` ("Premium (Lifetime)").
- Subscriptions: `premium_yearly` ("Premium (Yearly)"), one base plan,
  yearly, auto-renewing. Match the iPhone prices (£1.99 / year, £7.99 lifetime
  in the UK) and let Play convert the rest.
- Licence testing: add your Google account(s) under Setup → License testing so
  test purchases aren't charged.

## Countries
Production and testing: every country **except the EU/EEA** until trader
status and a public address are sorted (Countries/regions; untick the 27 EU
countries plus Iceland, Liechtenstein and Norway). The UK is fine.

## Testing
Closed testing → a track with at least **12 testers for 14 days** (all in
countries the app is available in). Upload the release bundle there first.

## Release bundle
`./gradlew bundleRelease` → `app/build/outputs/bundle/release/app-release.aab`,
signed with the upload key from `~/.camotrack/keystore.properties`. Use Play App
Signing (Google keeps the app signing key; you keep the upload key).
