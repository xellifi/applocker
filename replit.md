# AppLocker - Parental Control Dashboard

## Trial + Plan Gating (2026-04 refactor)
- `lib/shared/plan_gate.dart` is the single source of truth for feature gating. Plans store a `featuresMap` with 7 toggles: `appRestrictions`, `scheduleLock`, `appFilter`, `childMonitoring`, `liveLocation`, `chat`, `masterPin`, plus numeric limits (`deviceLimit`, `blockedAppsLimit`, `hiddenAppsLimit`).
- `PlanGate.requireForUser(context, uid, (f)=>f.<feature>)` shows a styled "Upgrade Required" dialog and routes to the Subscription page when blocked. Schedule Lock, App Restrictions, scheduled-window App Restrictions, and the Activity Monitoring view are all gated.
- **Trial plan = 3 days, 1 device, 1 app restriction**, no schedule lock / app filter / child monitoring. Anti-abuse: a SHA256 browser fingerprint stored in `/trial_fingerprints/` blocks repeat trials from the same browser (second account auto-falls back to Free), and a SHA256 of the device model stored in `/trial_devices/` blocks the same physical phone (e.g. RMX5078) from being paired again on a different parent's trial — enforced inside `FirebaseService.registerDevice`.
- Expired trial users are auto-redirected to the Subscriptions page by `_DashboardScreenState` and all device settings are paused via `_syncSubscriptionToDevices`.
- Super-admin Plan editor (`_showPlanDialog`, both desktop + mobile copies) now has 7 SwitchListTile feature toggles plus marketing-bullet text fields.
- Deploy: `cd AppLocker && flutter build web --target lib/dashboard/main_web.dart --release && firebase deploy --only hosting --project applocker-c39cf --token "$FIREBASE_TOKEN"`. Live: https://applocker-c39cf.web.app.

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

## Bug Fixes & Enhancements — April 2026 (Latest)

### Kotlin Scheduling Bug Fix
- **Root cause**: Flutter dashboard saves lock/app schedule times as `"HH:mm"` (24-hour), but `AppLockerBackgroundService.kt` was trying to parse them with `SimpleDateFormat("h:mm a", Locale.US)` (12-hour AM/PM) — causing silent parse failures so no schedule ever triggered.
- **Fix in `isScheduleActive()`**: Replaced `SimpleDateFormat` with direct `String.split(":")` parsing of `"HH:mm"` format.
- **App schedule logic fix in `isScheduledToBlockNow()`** (renamed from `isAppInAllowedWindow`): Fixed inverted logic — the old code treated the window as "allowed" but Flutter UI labels it "Block From / Block Until" (blocking window). Now correctly returns `true` when inside the blocking window.
- **`checkForegroundApp()` update**: Now checks both `blockedApps` (explicit block) AND `isScheduledToBlockNow()` (schedule window) — an app is blocked if either condition is true.

### Dashboard Chat & UI Improvements
- **`_MobileDeviceCard`** (Dashboard home): Converted to `StatefulWidget`. Streams real-time unread child-message count. Shows chat badge with count in top-right of card. Shows "Scheduled" indicator if any enabled lock schedule exists. Tapping the card navigates to My Devices page.
- **`_MobileDeviceListCard`** (My Devices page): Converted to `StatefulWidget`. Streams unread child message count; Chat button shows real badge count. Added reverse geocoding via Nominatim (OpenStreetMap) — shows suburb/city location label next to Online/Offline status.
- **`_DevActCircle`**: Updated `badge: true` → `badgeCount: int` so the badge shows the actual unread count number.
- **Chat read state**: `_MobileChatSheetState.initState` now calls `markMessagesRead(deviceId, 'child')` so badges clear when parent opens chat.
- **Admin clear chat**: Trash icon (`delete_sweep`) in the admin chat header opens a confirm dialog, then calls `FirebaseService.clearChatHistory()` which batch-deletes all messages from Firestore (clears for both sides permanently).
- **Child clear chat**: Trash icon in the child `ChildChatScreen` AppBar saves the current timestamp to SharedPreferences (`chat_cleared_at_{deviceId}`). The StreamBuilder filters out messages with timestamps before that stored time — visible only on the child's device; admin still sees full history.

## Recent Dashboard Bug Fixes & Enhancements (April 2026)
1. **My Devices**: Added remove device button to mobile device list cards
2. **App Controls (Mobile)**: Back button at top-right; empty state shows filter-specific message (e.g., "No blocked apps found")
3. **Schedules (Desktop)**: Edit button now fully functional — time picker for Device Lock rules, schedule dialog for App Restriction rules; converted `_SchedulesView` to StatefulWidget
4. **Location (Mobile + Desktop)**: Back navigation button added after Live Sync in both views
5. **Monitoring**: Chat heads/junk notifications pre-filtered before ListView build; missing sender defaults to "Me" instead of "Unknown"
6. **Subscriptions**: `_upgradePlan` replaced with full payment flow — GCash/Maya/Bank Transfer selection, QR code display, proof-of-payment URL input, transaction saved to `transactions` Firestore collection with `pending` status for admin approval
7. **Settings**: Initialization bug fixed — uses `_settingsInitialized` flag with `addPostFrameCallback` + `setState` to avoid duplicate calls
8. **Profile (Mobile + Desktop)**: Photo URL field added; avatar renders `NetworkImage` when URL present; camera icon toggles URL input; saves `photoURL` to Firestore `users` collection and Firebase Auth
9. **Live Activity Feed**: New `_ActivityFeedCard` on the dashboard overview (mobile + desktop) streams `/devices/{deviceId}/activity` for every paired device in parallel, merges & sorts by timestamp desc, shows 20 most recent events with color-coded icons (app blocks red, opens indigo, websites blue, messages green, calls/schedules amber, lock/unlock red/green), device-name chip, and live relative time ("2m ago") that auto-refreshes every 30s. Pulsing green dot indicates live status.
9. **Mobile Settings SMS Save Fix**: Added the Emergency SMS Number field and target device selector to mobile Settings, and changed mobile Settings saves to update the selected `devices/{id}` document using the same Firestore fields as desktop (`smsReceiverNumber`, child customisation, lock screen, and restricted screen fields).

## Child App Fixes (April 2026 — Latest)
1. **Lock Screen Chat & SMS Keyboard Gap**: Added 15px gap between the Android keyboard and both the Flutter chat bottom sheet (`AnimatedPadding` bottom = `viewInsets.bottom + 15`) and the native overlay panels (`attachKeyboardLift` bottom bumped from `dp(15)` to `dp(30)`).
2. **SMS Permission (SEND_SMS)**: Added runtime SEND_SMS permission request in `MainActivity.onResume`. Added `hasSmsPermission` and `requestSmsPermission` MethodChannel handlers. The child home screen now shows an "SMS Permission" setup card and checks the grant status in the periodic timer.
3. **SMS Conversation Log + Accurate Status**: SMS messages are now saved to Firestore `messages` collection (`sender: 'child'`, `type: 'sms'`, `text: '📲 SMS: ...'`) so they appear in the chat conversation flow. Replaced fire-and-forget `sendMultipartTextMessage` with a `PendingIntent` BroadcastReceiver so the status reflects the real result — success, no signal, radio off, or generic failure (including no credit/load).

## Previous Child App Fixes (April 2026)
1. **Locked Overlay Message/SMS Keyboard Fix**: Recreated the native Android MESSAGE and SMS overlay panels with a keyboard-height listener that lifts and resizes the active panel above the Android keyboard. Chat still sends/receives through Firestore, and SMS still sends to the configured emergency number.
2. **Flutter Overlay Fallback**: Updated the Flutter child chat bottom sheet to shrink and animate above `viewInsets.bottom` so the message input stays visible when the keyboard opens.

## Replit Migration Notes
- Dependencies are restored with `flutter pub get` inside `AppLocker/`.
- The Replit workflow serves the built dashboard from `AppLocker/build/web` on port 5000.
- A missing `web/favicon.png` was restored from the existing Flutter icon assets to prevent unnecessary 404s in the preview logs.
- PWA install flow now preserves the native browser install prompt when available, detects embedded preview contexts where the prompt cannot appear, and offers a direct top-level install page before falling back to manual Add to Home Screen instructions.
- Firebase Hosting production URL: `https://applocker-c39cf.web.app`. The latest PWA install changes were deployed there, and Firebase headers now prevent stale caching for `flutter_service_worker.js`, `main.dart.js`, and `flutter_bootstrap.js`.
- Dashboard state now persists onboarding completion, selected menu, and light/dark theme in browser storage so accidental refreshes do not send logged-in users back to the first page. The pair-new-device dialog was redesigned as a responsive QR/PIN modal with the clipped bottom Close button removed.
