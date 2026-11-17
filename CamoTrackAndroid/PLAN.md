# Camo Track for Android

A native Kotlin + Jetpack Compose app. It reads the same published data as
the iPhone app (`Data/<game>/` on jsDelivr, pictures from camo-track.app), so
one `publish_data.py` run feeds both. The app code is written again; the data,
image host, overlay Worker and push Worker are shared.

## Build and run

    export JAVA_HOME=$(/usr/libexec/java_home -v 17)
    export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
    ./gradlew assembleDebug
    $ANDROID_HOME/emulator/emulator -avd pixel8 &      # Pixel 8, Android 15
    $ANDROID_HOME/platform-tools/adb install -r app/build/outputs/apk/debug/app-debug.apk

## Done (2026-11-17)

- Proof of concept: MW4 Multiplayer's weapons by class from `weapons.json`,
  each weapon's camos from `multiplayer.json`, pictures through Coil, in the
  iPhone app's colours.

## First release (aim: the next Call of Duty's launch)

1. Every game in `games.json` and its modes; the game and mode picker.
2. Progress: ticking camos, counters, weapon levels and Prestige, saved on
   the phone in the same model as the iPhone app (keys like
   `camo|<mode>|<weaponId>|<itemId>`), so a later sync can share it.
3. Completionist, Mastery, Prestige camos, events (Live now), Stats.
4. Data refresh: manifest versions, cached files, background refresh
   (WorkManager).
5. Premium through Google Play Billing (yearly and lifetime), ads through
   LevelPlay's Android SDK with Android ad units.
6. Push: Firebase Cloud Messaging, sent by the push Worker beside APNs.
7. Stream overlay: the same `/api/overlay` calls as the iPhone app.
8. The seven languages, from the iPhone app's Localizable.strings.

## Later

- Hajin (DMZ map, guide, stash scan with ML Kit), widgets (Glance), sync
  between devices (Google sign-in or a sync Worker), share cards, camo app
  icons (activity aliases).

## Google Play

- A personal developer account ($25) has to run a closed test with at least
  12 testers for 14 days before going public: start it early, alongside the
  build.
- Data safety form (ads, purchases, push), the ads declaration, content rating.
