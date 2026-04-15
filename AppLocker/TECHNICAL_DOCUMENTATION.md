# 🛡️ Smart Blocker: Technical Documentation

This document provides a comprehensive technical overview of the **Smart Blocker** platform. It is designed to assist developers and AI agents in understanding the system's architecture, native implementation, and real-time synchronization mechanisms.

---

## 🏗️ 1. Architecture Overview
The platform uses a **Parent-Child Hybrid** model:
- **Admin Dashboard (PWA)**: A Flutter Web application for multi-device command-and-control.
- **Child Application (APK)**: A Flutter Android application with a persistent Kotlin background service for system-level monitoring.
- **Backend (Firebase)**: Firestore serves as the real-time message bus and state repository.

---

## 🚀 2. Core Features & How They Work

### 🏁 Full Device Lock (Manual & Scheduled)
- **What it does**: Completely prevents the child from using the device (except for emergency calls).
- **How it works**:
    1. Parent clicks **"Lock"** in the Dashboard.
    2. `locked: true` is updated in Firestore.
    3. The Child App's `FirestoreSubscription` detects the change.
    4. `ChildLockController` triggers `bringToForeground` via **MethodChannel**.
    5. The `LockOverlay` (with the PIN entry and Tasks) is displayed.
    6. **Native persistence**: The `MainActivity` uses `startLockTask()` to pin the app to the screen.

### 🚫 Smart App Blocker (Smart Intercept)
- **What it does**: Blocks specific apps (e.g., YouTube, Games) while allowing the device to remain unlocked for other uses.
- **How it works**:
    1. Parent adds an app to the **Blocked List** in the Dashboard.
    2. The list is synced to the child's `SharedPreferences` and the Native Kotlin service.
    3. `AppLockerBackgroundService.kt` runs a 1-second loop using `UsageStatsManager`.
    4. If a blocked app (e.g., Netflix) moves to the foreground, the service immediately launches the AppLocker UI.
    5. A `MethodChannel` call (`onAppBlocked`) tells the Flutter UI to show the **BlockedAppOverlay**.

### 🎨 Decoupled Messaging System
- **What it does**: Shows different information depending on *why* the device is restricted.
- **How it works**:
    - **Task Center (Locked Mode)**: Uses `taskTitle` and `taskList` (e.g., "Mother's To-Do List"). Displayed on the device-wide lock overlay.
    - **Warning Center (Block Mode)**: Uses `warningTitle` and `warningList` (e.g., "Rental Agreement"). Displayed with dynamic blinking animations when an app is restricted.

### 🔋 Real-time Monitoring (GPS + Battery)
- **What it does**: Parents see the child's location and battery level in real-time.
- **How it works**:
    - Every 15 minutes (via `WorkManager`) or 30 seconds (via in-app `Timer`), the Child App fetches GPS and battery data.
    - This data is pushed to `/devices/{deviceId}` in Firestore.
    - The Admin Dashboard listens and updates the map and battery icons instantly.

---

## 🛠️ 3. Native Android Core (Kotlin)

### `AppLockerBackgroundService.kt`
- **Role**: The "Silent Guard".
- **Mechanism**: A `Foreground Service` (with a non-dismissible notification) that monitors `UsageStats`.
- **Persistence**: Registered with `BOOT_COMPLETED` to start automatically when the phone reboots.

### `MainActivity.kt`
- **Role**: The "Bridge".
- **Interactions**:
    - **Screen Pinning**: Handles `startLockTask()`/`stopLockTask()` for tamper-proof locking.
    - **Identity Bridge**: Captures Intent Extras from the background service to trigger the correct restriction UI.
    - **MethodChannel**: Provides a two-way communication pipe (`com.parentalcontrol/lock`) between Dart and Kotlin.

---

## 📊 4. Data Model (Firestore)

The system revolves around the `DeviceModel` stored in `/devices/{id}`.

| Field | Type | Description |
| :--- | :--- | :--- |
| `locked` | Boolean | Global lock state (True = Full Lock). |
| `lockSchedules` | List<Map> | Time-of-day auto-lock blocks. |
| `taskList` | List<String> | Points/Tasks displayed during full lock. |
| `warningList` | List<String> | Rules displayed during specific app blocks. |
| `hiddenApps` | List<String> | Package names monitored by the Native Guard. |
| `pin` | String | Bypass code (Default: 1234). |
| `battery` | Integer | Last known battery percentage. |
| `lat` / `lng` | Double | Last known location coordinates. |

---

## 📦 5. Core Dependencies (Plugins)

- `firebase_core/auth/firestore`: Backend infrastructure.
- `geolocator`: GPS coordinate fetching.
- `battery_plus`: System battery monitoring.
- `workmanager`: Periodic background tasks (15 min intervals).
- `flutter_map`: Map visualization on the Dashboard.
- `permission_handler`: Managing UsageStats and Overlay permissions.

---

## 📝 6. Developer Guidelines
- **Building the Child APK**: Use `flutter build apk --target lib/child/main_child.dart --release`.
- **Native Edits**: Any changes to app blocking *must* be reflected in both `AppLockerBackgroundService.kt` (for detection) and `home_screen.dart` (for display).
- **Service Security**: The `SYSTEM_ALERT_WINDOW` and `PACKAGE_USAGE_STATS` permissions are critical for the app to function.

---

*Documentation compiled by Antigravity (AI Coding Assistant) for the Smart Blocker Platform.* 🛡️📖
