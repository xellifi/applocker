# AppLocker - Build and Install Commands

## Child APK (Phone App)
```bash
# Clean build
flutter clean

# Build release APK
flutter build apk --release --target lib/child/main_child.dart

# Install to device
flutter install
```

## Parent Dashboard (Web)
```bash
# Run web dashboard in Chrome
flutter run --target lib/dashboard/main_web.dart -d chrome

# Or build for deployment
flutter build web --target lib/dashboard/main_web.dart
```

## Quick Install (after changes)
```bash
# Single command to build and install
flutter build apk --release --target lib/child/main_child.dart && flutter install
```

## Notes
- Child APK targets: `lib/child/main_child.dart`
- Parent Dashboard targets: `lib/dashboard/main_web.dart`
- Use `flutter clean` if you encounter build errors
- Make sure device is connected via USB debugging
