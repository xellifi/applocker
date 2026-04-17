// lib/main.dart
// Main entry point - determines which app to run based on build configuration
// 
// Usage:
// - Child APK: flutter build apk --release --dart-define=APP_MODE=child
// - Web Dashboard: flutter build web --target lib/dashboard/main_web.dart
// - Default (development): runs child app

import 'package:flutter/foundation.dart';
import 'child/main_child.dart' as child_app;

// Only import web app when on web platform
Future<void> main() async {
  if (kIsWeb) {
    // For web, we need to use conditional import
    // This will be handled by the web-specific build target
    // For now, just run child app as fallback
    await child_app.main();
  } else {
    // Child app for Android
    await child_app.main();
  }
}
