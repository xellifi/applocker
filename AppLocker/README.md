# AppLocker - Enhanced Parental Control App

A comprehensive Flutter parental control app with advanced restriction modes, modern dashboard UI, and robust native Android integration.

## Features Overview

### Existing Locking Functionality (Preserved)
- Full device lock with PIN protection
- Native system overlay covering all apps
- Firebase remote control integration
- Background service monitoring
- **This functionality remains completely unchanged and preserved**

### New Features Added

#### 1. Basic Mode - App Overlay Restriction
When a parent restricts an app (e.g., YouTube), a full-screen overlay blocks the child from using it when they open it. The app icon remains visible.

**Technical Implementation:**
- Android `AppOverlayService` using `TYPE_APPLICATION_OVERLAY`
- `SYSTEM_ALERT_WINDOW` permission handling
- Foreground service with persistent overlay
- MethodChannel integration with Flutter

**How it works:**
1. Parent selects apps to restrict from dashboard
2. Child opens restricted app
3. Full-screen overlay appears immediately
4. Overlay shows friendly message: "This app is restricted by your parent"
5. Child cannot dismiss or interact with app underneath
6. Works even after force-close and reopen

#### 2. Advanced Mode - Hide App Icons
Parent can completely hide selected app icons from the child's home screen and app drawer, as if the app doesn't exist.

**Technical Implementation:**
- Android `AppHidingService` with multiple approaches:
  - Primary: `PackageManager.setComponentEnabledSetting()` to disable launcher activities
  - Secondary: Device Policy Manager `setApplicationHidden()` if Device Owner
- Component state management
- Persistent hiding across device reboots

**How it works:**
1. Parent selects apps to hide from dashboard
2. App icons disappear from launcher and app drawer
3. Child cannot find or launch hidden apps through normal navigation
4. Parent can unhide apps any time from dashboard
5. Hidden state persists across device reboots

#### 3. Modern Dashboard UI
Complete redesign with beautiful, modern, user-friendly interface.

**Design Language:**
- Clean card-based layout throughout
- Consistent color system: Deep indigo primary with semantic colors
- Typography: Clear hierarchy with Inter font
- Rounded corners (12-16px radius)
- Generous padding and whitespace
- Smooth transitions and animations
- Light and dark mode support

**Dashboard Screens:**
- **Home Screen**: Greeting, quick stats, child profiles, activity feed
- **App Management**: Searchable app list with restriction modes
- **Child Profile**: Device info, schedules, emergency controls
- **Settings**: PIN management, notifications, mode explanations

## Architecture

### Flutter Structure
```
lib/
 dashboard/
   screens/           # Main dashboard screens
   theme/            # Theme system and providers
   widgets/          # Reusable UI components
 shared/
   models/           # Data models (Hive, Firebase)
   services/         # Business logic services
 child/              # Child app (preserved)
```

### Android Native Services
```
android/app/src/main/kotlin/com/parentalcontrol/applocker/
 MainActivity.kt           # MethodChannel handlers (enhanced)
 AppOverlayService.kt      # Basic Mode overlay service
 AppHidingService.kt       # Advanced Mode app hiding
 LockOverlayService.kt     # Existing lock service (preserved)
 AppLockerBackgroundService.kt  # Background monitoring (preserved)
```

### Data Persistence
- **Local**: Hive database for restriction settings
- **Remote**: Firebase Firestore for sync and remote control
- **Models**: `AppRestriction`, `ChildProfile` with code generation

## MethodChannel API

### Basic Mode (Overlay)
```dart
// Show overlay for restricted app
await channel.invokeMethod('showAppOverlay', {'packageName': 'com.app.name'});

// Hide current overlay
await channel.invokeMethod('hideAppOverlay');

// Check if overlay service is running
final isRunning = await channel.invokeMethod<bool>('isOverlayServiceRunning');
```

### Advanced Mode (App Hiding)
```dart
// Start hiding service
await channel.invokeMethod('startHidingService');

// Hide specific app
await channel.invokeMethod('hideAppPackage', {'packageName': 'com.app.name'});

// Unhide specific app
await channel.invokeMethod('unhideAppPackage', {'packageName': 'com.app.name'});

// Sync multiple hidden apps
await channel.invokeMethod('syncHiddenApps', {'packages': ['app1', 'app2']});
```

## Permission Requirements

### Android Permissions
```xml
<!-- Existing (preserved) -->
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" />
<uses-permission android:name="android.permission.BIND_DEVICE_ADMIN" />

<!-- New for enhanced features -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA" />
```

### Permission Handling Flow
1. **SYSTEM_ALERT_WINDOW**: Required for overlays
2. **PACKAGE_USAGE_STATS**: Required for app monitoring
3. **BIND_DEVICE_ADMIN**: Required for advanced app hiding
4. Graceful permission request flows with fallback options

## Setup Instructions

### 1. Install Dependencies
```bash
flutter pub get
flutter packages pub run build_runner build
```

### 2. Build Child APK
```bash
flutter build apk --release --target lib/child/main_child.dart
```

### 3. Build Web Dashboard
```bash
flutter build web --target lib/dashboard/main_web.dart
```

### 4. Run Development
```bash
# Child app
flutter run --dart-define=APP_MODE=child -d <android-device>

# Parent dashboard
flutter run --target lib/dashboard/main_web.dart -d chrome
```

## Usage Guide

### For Parents

#### Setting Up Basic Mode (Overlay)
1. Open dashboard and go to "Apps" screen
2. Search for app you want to restrict (e.g., YouTube)
3. Tap on app and select "Overlay (Basic)" mode
4. Save changes
5. When child opens the app, they'll see a friendly overlay

#### Setting Up Advanced Mode (Hide Apps)
1. Go to "Apps" screen in dashboard
2. Select apps you want to completely hide
3. Choose "Hidden (Advanced)" mode
4. Save changes
5. App icons will disappear from child's device

#### Managing Child Profiles
1. Go to "Children" screen
2. Tap on child profile to view details
3. Set bedtime schedules, manage restrictions
4. Use emergency controls for immediate actions

#### Changing PIN
1. Go to "Settings" screen
2. Tap on "Parent PIN"
3. Enter current PIN and new PIN
4. Confirm new PIN

### For Developers

#### Adding New Restriction Modes
1. Update `RestrictionMode` enum in `app_restriction_model.dart`
2. Add corresponding color and display logic in `app_theme.dart`
3. Implement native service logic in Android
4. Update MethodChannel handlers in `MainActivity.kt`
5. Add UI components for mode selection

#### Extending Dashboard
1. Create new screen in `dashboard/screens/`
2. Add navigation entry in `dashboard_shell.dart`
3. Create reusable widgets in `dashboard/widgets/`
4. Follow existing design patterns and theme usage

## Testing

### Feature Validation
- [x] Existing lock functionality preserved
- [x] Basic Mode overlay appears when restricted app opened
- [x] Advanced Mode hides app icons from launcher
- [x] Dashboard UI renders correctly in light/dark mode
- [x] Permission flows work properly
- [x] Data persistence with Hive works
- [x] Firebase integration maintains sync

### Regression Testing
- [x] Original app locking still functions
- [x] Background services continue monitoring
- [x] FCM commands still work
- [x] Child app pairing process unchanged
- [x] Device admin functionality preserved

## Troubleshooting

### Common Issues

#### Overlay Not Showing
1. Check `SYSTEM_ALERT_WINDOW` permission
2. Ensure overlay service is running
3. Verify app restriction mode is set to "basic"

#### Apps Not Hiding
1. Check Device Admin permissions
2. Verify hiding service is started
3. Ensure app restriction mode is set to "advanced"
4. Check if device is in Device Owner mode (for full functionality)

#### Dashboard Not Loading
1. Ensure Firebase is properly configured
2. Check network connectivity
3. Verify authentication state
4. Check console for Firebase errors

### Debug Commands
```bash
# Check Android logs for service issues
adb logcat | grep "AppLocker"

# Verify overlay permission
adb shell dumpsys package com.parentalcontrol.applocker | grep overlay

# Check device admin status
adb shell dpm list-admins
```

## Future Enhancements

### Planned Features
- iOS Screen Time API integration
- Time-based restrictions (schedules)
- Geofencing-based controls
- Web filtering integration
- Usage analytics and reports
- Multi-language support

### Technical Improvements
- Better error handling and recovery
- Offline mode support
- Performance optimizations
- Enhanced security measures
- Automated testing suite

## Contributing

When contributing to this project:
1. Preserve existing locking functionality
2. Follow established code patterns
3. Test both Basic and Advanced modes
4. Update documentation for new features
5. Ensure UI consistency with design system

## License

This project maintains the same license as the original AppLocker application.
