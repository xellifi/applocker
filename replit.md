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
serve -s AppLocker/build/web -l 5000 --no-clipboard
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
