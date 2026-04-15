# AppLocker — Setup & Build Guide

## 🔥 Step 1: Firebase Console

1. Go to https://console.firebase.google.com
2. New Project → Name: `AppLocker`
3. **Add Android App**: Package = `com.parentalcontrol.applocker` → Download `google-services.json` → place at `android/app/google-services.json`
4. **Add Web App**: Nickname = `AppLocker PWA` → Enable Hosting
5. Enable **Authentication** → Email/Password
6. Enable **Firestore** → Start in test mode
7. Paste these **Security Rules**:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /devices/{deviceId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && (
        request.auth.uid == resource.data.parentUid ||
        request.auth.uid == resource.data.childUid
      );
    }
    match /users/{userId} {
      allow read, write: if request.auth.uid == userId;
    }
  }
}
```

---

## ⚙️ Step 2: Flutter Setup

```
cd "C:\Users\User\Desktop\AppLocker"

# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Generate lib/firebase_options.dart (select Android + Web)
flutterfire configure

# Install all packages
flutter pub get
```

After flutterfire configure, update lib/shared/firebase_service.dart:

```dart
import '../firebase_options.dart';

// In initFirebase():
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

---

## 📱 Step 3: Child APK

```
# Debug run on connected device
flutter run --target lib/child/main_child.dart -d <device-id>

# Release APK
flutter build apk --release --target lib/child/main_child.dart

# Install via ADB
adb install build/app/outputs/flutter-apk/app-release.apk
```

First launch: Sign Up → note the 8-char Pairing Code → grant all permissions.

---

## 🌐 Step 4: Parent PWA

```
# Dev mode
flutter run --target lib/dashboard/main_web.dart -d chrome

# Build + deploy
flutter build web --target lib/dashboard/main_web.dart --release
firebase deploy --only hosting
```

---

## 🔗 Step 5: Pair Devices

1. Parent signs up on dashboard
2. Enters child's 8-char Pairing Code shown on child phone
3. Device appears in sidebar with live data

---

## ✅ Test Checklist

- Lock: Dashboard Lock button → child shows black overlay
- PIN: Enter "1234" → overlay dismisses
- Force: Dashboard Force button → overlay clears instantly
- Timeout: Wait 5 min locked → auto-unlocks (safety net)
- Heartbeat: Unlock from dashboard → clears within 30s
- Battery: Child < 20% → red badge on dashboard
- Location: Wait 15 min → map pin updates
- Emergency: Tap top-left corner 10x fast → Android Settings opens

```
# Verify WorkManager tasks running
adb shell dumpsys jobscheduler | findstr parental
```

---

## 🛟 Recovery Guide

| Situation | Fix |
|-----------|-----|
| Forgot PIN | Default is "1234" |
| Overlay stuck | Wait 5 minutes (auto-timeout) |
| Dashboard offline | Tap top-left 10x → Settings escape |
| App frozen | Settings > Apps > AppLocker > Force Stop |
| Safe mode | Hold Power > long-press "Power off" > Safe Mode |
| Uninstall | Settings > Security > Device Admin Apps > AppLocker > Deactivate > then Uninstall |

---

## IMPORTANT NOTES

WARNING: google-services.json MUST be at android/app/google-services.json before building.

IMPORTANT: Min SDK = 24 (Android 7.0+). Older devices not supported.

NOTE: Uses Device Admin (not Device Owner). Easy uninstall via Settings. No ADB needed.

TIP: To make PIN configurable: store pin in Firestore /devices/{deviceId} and read in LockOverlay.
