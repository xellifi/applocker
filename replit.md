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
- **Locked Page**: Yellow `#FBBC05` background. Lock icon in circle (tap to enter PIN dialog). "LOCKED" bold 42sp. Task box (black border, "YOUR TASKS" title, centered task items in CAPS). "SEND MESSAGE HERE" placeholder button. Footer text.
- **Restricted App Page**: Red `#F44336` background. ⚠ triangle emoji. "RESTRICTED" bold white. White-bordered tasks box. White "GOT IT" button.

### Admin Settings (New Fields)
Three new Firestore fields added to device documents:
- `parentQuote` — quote text shown on the child's unlock screen
- `profileImageUrl` — parent photo URL shown with green border on unlock screen
- `unlockGreeting` — the "Enjoy Your Day" text under "Device Unlocked"

These are configurable in the "UNLOCK PAGE CUSTOMISATION" section in Settings.

## Running the App

### Development
The workflow "AppLocker Dashboard" serves the pre-built Flutter web app on port 5000 using `serve`.

### Building
To rebuild the Flutter web app:
```bash
cd AppLocker && flutter pub get
flutter build web --target lib/dashboard/main_web.dart --release
```

### Workflow Command
```
npx serve -s AppLocker/build/web -l 5000 --no-clipboard
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
