# AppLocker - Parental Control Dashboard

## Overview
A Flutter-based parental control platform consisting of:
- **Parent Dashboard (PWA)**: Web app for managing child devices remotely
- **Child App (Android APK)**: Android application for monitoring and restricting device usage

## Architecture

### Tech Stack
- **Framework**: Flutter (Dart) - version 3.32.0
- **Backend**: Firebase (Auth, Firestore, Cloud Messaging)
- **Database**: Firestore (real-time sync between parent dashboard and child devices)
- **Package Manager**: Pub (Flutter)

### Project Structure
```
AppLocker/
├── lib/
│   ├── child/          # Child Android app entry point and logic
│   ├── dashboard/      # Parent web dashboard
│   │   ├── main_web.dart       # Entry point for the web PWA
│   │   └── dashboard_screen.dart
│   ├── shared/         # Shared models and services
│   │   ├── models/
│   │   └── firebase_service.dart
│   └── firebase_options.dart
├── android/            # Native Android code (Kotlin)
├── web/                # Flutter web config files
├── build/web/          # Built web output (served by workflow)
└── pubspec.yaml        # Flutter dependencies
```

## UI Design (Latest)

### Child App Screens
- **Unlock Page (Home)**: Light purple (`#F0EDF8`) background. White AppBar with "AppLocker" bold black + green version badge. Status row card (online indicator + color-coded battery: green ≥50%, orange 20–49%, red <20%). Quote/profile card (❤ doodle + quote text + profile image with green border). Unlock card (open lock icon + "Device Unlocked" + "Enjoy Your Day" greeting).
- **Locked Page**: Yellow `#FBBC05` background. Lock icon in circle (tap to enter PIN dialog). "LOCKED" bold 42sp. Task box (black border, "YOUR TASKS" title, centered task items in CAPS). MESSAGE and SMS actions open native keyboard-aware overlay panels above the Android keyboard.
- **Restricted App Page**: Red `#F44336` background. ⚠ triangle emoji. "RESTRICTED" bold white. White-bordered tasks box. White "GOT IT" button.

### Admin Settings (New Fields)
Three new Firestore fields added to device documents:
- `parentQuote` — quote text shown on the child's unlock screen
- `profileImageUrl` — parent photo URL shown with green border on unlock screen
- `unlockGreeting` — the "Enjoy Your Day" text under "Device Unlocked"

These are configurable in the "UNLOCK PAGE CUSTOMISATION" section in Settings.

## Running the App

### Development
The workflow "Start application" serves the pre-built Flutter web app on port 5000 using Python's static HTTP server.

### Building
To rebuild the Flutter web app:
```bash
cd AppLocker && flutter pub get
flutter build web --target lib/dashboard/main_web.dart --release
```

### Workflow Command
```
python3 -m http.server 5000 --directory AppLocker/build/web
```

## Deployment
Configured as a static deployment:
- **Build**: `cd AppLocker && flutter pub get && flutter build web --target lib/dashboard/main_web.dart --release`
- **Public Dir**: `AppLocker/build/web`

## Firebase Configuration
- Firebase project: `applocker-c39cf`
- Config files: `AppLocker/lib/firebase_options.dart`, `google-services.json`
- Firebase hosting: `https://applocker-c39cf.web.app`

## Features
- Full device lock and smart app blocking
- Real-time GPS and battery monitoring
- Remote commands via Firebase
- Advanced mode (hiding app icons)
- Parent dashboard with device management
- Child ↔ Parent real-time chat (accessible from the lock screen)
- App restriction schedule enforcement fix (DateFormat en_US locale + Intent serialization fix)
- Image upload for parent profile photo in admin settings (Firebase Storage)
- Lock screen: PIN removed from lock icon tap; 10-tap hidden emergency unlock
- Restricted mode: red/pink background, GOT IT button with matching rounded corners

## Recent Dashboard Bug Fixes & Enhancements (April 2026)
1. **My Devices**: Added remove device button to mobile device list cards
2. **App Controls (Mobile)**: Back button at top-right; empty state shows filter-specific message (e.g., "No blocked apps found")
3. **Schedules (Desktop)**: Edit button now fully functional — time picker for Device Lock rules, schedule dialog for App Restriction rules; converted `_SchedulesView` to StatefulWidget
4. **Location (Mobile + Desktop)**: Back navigation button added after Live Sync in both views
5. **Monitoring**: Chat heads/junk notifications pre-filtered before ListView build; missing sender defaults to "Me" instead of "Unknown"
6. **Subscriptions**: `_upgradePlan` replaced with full payment flow — GCash/Maya/Bank Transfer selection, QR code display, proof-of-payment URL input, transaction saved to `transactions` Firestore collection with `pending` status for admin approval
7. **Settings**: Initialization bug fixed — uses `_settingsInitialized` flag with `addPostFrameCallback` + `setState` to avoid duplicate calls
8. **Profile (Mobile + Desktop)**: Photo URL field added; avatar renders `NetworkImage` when URL present; camera icon toggles URL input; saves `photoURL` to Firestore `users` collection and Firebase Auth

## Recent Child App Fixes (April 2026)
1. **Locked Overlay Message/SMS Keyboard Fix**: Recreated the native Android MESSAGE and SMS overlay panels with a keyboard-height listener that lifts and resizes the active panel above the Android keyboard. Chat still sends/receives through Firestore, and SMS still sends to the configured emergency number.
2. **Flutter Overlay Fallback**: Updated the Flutter child chat bottom sheet to shrink and animate above `viewInsets.bottom` so the message input stays visible when the keyboard opens.

## Replit Migration Notes
- Dependencies are restored with `flutter pub get` inside `AppLocker/`.
- The Replit workflow serves the built dashboard from `AppLocker/build/web` on port 5000.
- A missing `web/favicon.png` was restored from the existing Flutter icon assets to prevent unnecessary 404s in the preview logs.
- PWA install flow now preserves the native browser install prompt when available, detects embedded preview contexts where the prompt cannot appear, and offers a direct top-level install page before falling back to manual Add to Home Screen instructions.
- Firebase Hosting production URL: `https://applocker-c39cf.web.app`. The latest PWA install changes were deployed there, and Firebase headers now prevent stale caching for `flutter_service_worker.js`, `main.dart.js`, and `flutter_bootstrap.js`.
- Dashboard state now persists onboarding completion, selected menu, and light/dark theme in browser storage so accidental refreshes do not send logged-in users back to the first page. The pair-new-device dialog was redesigned as a responsive QR/PIN modal with the clipped bottom Close button removed.
