// lib/child/main_child.dart
// Child APK entry point
// Build: flutter build apk --release --dart-define=APP_MODE=child
//        flutter run --dart-define=APP_MODE=child
//
// TEST: Run `flutter run --dart-define=APP_MODE=child -d <android-device-id>`
// TEST: Verify overlay appears after `Lock` command from dashboard

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/firebase_service.dart';
import 'background_service.dart';
import 'home_screen.dart';
import 'scanner_screen.dart';

// Platform channel for device admin / lock task / native overlay
const _platform = MethodChannel('com.parentalcontrol/lock');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation on child device
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Init Firebase
  await FirebaseService.initFirebase();

  // Handle foreground FCM messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('//TEST: Foreground FCM: ${message.data}');
    _handleFCMCommand(message.data['command']);
  });

  // Handle FCM tap when app is in background (not killed)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('//TEST: FCM tap opened app: ${message.data}');
    _handleFCMCommand(message.data['command']);
  });

  runApp(const ChildApp());
}

/// Handle FCM command string
void _handleFCMCommand(String? command) {
  if (command == null) return;
  debugPrint('//TEST: Handling FCM command: $command');
  switch (command) {
    case 'force_unlock':
    case 'hide_overlay':
      ChildLockController.instance.unlock();
      break;
    case 'show_overlay':
      ChildLockController.instance.lock();
      break;
  }
}

// ─── ChildLockController (global singleton) ──────────────────────────────────

/// Global lock state controller — decoupled from UI widgets
/// Now triggers NATIVE SYSTEM OVERLAY instead of just Flutter widget
class ChildLockController extends ChangeNotifier {
  static ChildLockController? _instance;
  static ChildLockController get instance =>
      _instance ??= ChildLockController._();
  ChildLockController._();

  bool _locked = false;
  bool get locked => _locked;

  String _deviceId = '';
  String _pin = '1234';

  void setDeviceId(String id) => _deviceId = id;
  void setPin(String pin) => _pin = pin;

  void lock() {
    if (!_locked) {
      _locked = true;
      notifyListeners();
      debugPrint('//TEST: ChildLockController -> LOCKED');
      
      // Show the NATIVE system overlay (covers ALL apps, home screen, etc.)
      _showNativeOverlay();
      
      // Also bring Flutter app to foreground as backup
      _platform.invokeMethod('bringToForeground').catchError((e) {
        debugPrint('//TEST: bringToForeground error: $e');
      });
    }
  }

  void unlock() {
    if (_locked) {
      _locked = false;
      notifyListeners();
      debugPrint('//TEST: ChildLockController -> UNLOCKED');
      
      // Hide the native system overlay
      _hideNativeOverlay();
    }
  }

  /// Show native Android system overlay (SYSTEM_ALERT_WINDOW)
  /// This draws ON TOP of ALL apps — home screen, other apps, everything
  Future<void> _showNativeOverlay() async {
    try {
      await _platform.invokeMethod('showNativeOverlay', {
        'pin': _pin,
        'deviceId': _deviceId,
      });
      debugPrint('//TEST: Native system overlay SHOWN');
    } catch (e) {
      debugPrint('//TEST: showNativeOverlay error: $e');
      // Fallback: just bring the app to foreground (Flutter overlay still works)
    }
  }

  /// Hide native Android system overlay
  Future<void> _hideNativeOverlay() async {
    try {
      await _platform.invokeMethod('hideNativeOverlay');
      debugPrint('//TEST: Native system overlay HIDDEN');
    } catch (e) {
      debugPrint('//TEST: hideNativeOverlay error: $e');
    }
  }
}

// ─── Child App ────────────────────────────────────────────────────────────────

class ChildApp extends StatelessWidget {
  const ChildApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppLocker Child',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChildInitScreen(),
    );
  }
}

// ─── Child Init Screen (post-auth) ────────────────────────────────────────────

class ChildInitScreen extends StatefulWidget {
  const ChildInitScreen({super.key});

  @override
  State<ChildInitScreen> createState() => _ChildInitScreenState();
}

class _ChildInitScreenState extends State<ChildInitScreen> {
  bool _initialized = false;
  String _status = 'Initializing...';
  String _pairingCode = ''; // 6-digit code for dashboard input
  StreamSubscription? _pairingSubscription;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _pairingSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      setState(() => _status = 'Getting device ID...');
        final deviceId = await _getDeviceId();
      debugPrint('//TEST: Device ID: $deviceId');

      setState(() => _status = 'Requesting permissions...');
      await _requestPermissions();

      // SILENT SIGN-IN: Child device writes (e.g. installedApps) require an authenticated uid
      // matching Firestore rules. Anonymous auth must be enabled in Firebase Console.
      try {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
          debugPrint('//TEST: Silent Anonymous Sign-in successful');
        }
      } catch (e) {
        debugPrint('//TEST: Silent sign-in error: $e');
      }
      if (FirebaseAuth.instance.currentUser == null) {
        setState(() {
          _status =
              'Sign-in failed. In Firebase Console → Authentication → Sign-in method, enable Anonymous.';
          _initialized = true;
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      var parentUid = prefs.getString('parentUid') ?? '';

      if (parentUid.isEmpty) {
        setState(() {
          _status = 'Device Unpaired';
          _initialized = true;
        });
      } else {
        _finalSetup(deviceId, parentUid);
      }
    } catch (e) {
      debugPrint('//TEST: Init error: $e');
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _finalSetup(String deviceId, String parentUid) async {
    try {
      setState(() => _status = 'Registering device...');
      final uid = FirebaseService.instance.currentUid!;
      
      String? modelName;
      try {
        final info = DeviceInfoPlugin();
        final android = await info.androidInfo;
        modelName = android.model; // the model of the phone
      } catch (e) {
        debugPrint('//TEST: Failed to get device model: $e');
      }
      
      await FirebaseService.instance.registerDevice(
        deviceId: deviceId,
        childUid: uid,
        parentUid: parentUid,
        model: modelName,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deviceId', deviceId);

      // Set deviceId on the lock controller so it can pass it to native overlay
      ChildLockController.instance.setDeviceId(deviceId);

      setState(() => _status = 'Initializing FCM...');
      await FirebaseService.instance.initFCM(deviceId: deviceId);

      // setState(() => _status = 'Starting background service...');
      // await ChildBackgroundService.initialize(deviceId: deviceId);

      // Start the native background service that polls Firestore
      // This is the KEY — it runs even when Flutter is not visible
      try {
        await _platform.invokeMethod('startBackgroundService', {
          'deviceId': deviceId,
          'pin': '1234',
        });
        debugPrint('//TEST: Native background service started with deviceId=$deviceId');
      } catch (e) {
        debugPrint('//TEST: startBackgroundService error: $e');
      }

      setState(() {
        _status = 'Ready!';
        _initialized = true;
      });

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChildHomeScreen(deviceId: deviceId),
          ),
        );
      }
    } catch (e) {
      debugPrint('//TEST: Final setup error: $e');
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _startQRScan() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );

    if (result != null && result.containsKey('parentId')) {
      final parentUid = result['parentId'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('parentUid', parentUid);
      
      final deviceId = await _getDeviceId();
      _finalSetup(deviceId, parentUid);
    }
  }

  Future<void> _pairWithCode(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.length != 6) return;
    setState(() => _status = 'Verifying code $cleanCode...');
    debugPrint('//TEST: Attempting pairing with code: $cleanCode');
    
    final parentUid = await FirebaseService.instance.getParentUidByCode(cleanCode);
    if (parentUid != null) {
      debugPrint('//TEST: Pairing SUCCESS! Parent UID: $parentUid');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('parentUid', parentUid);
      final deviceId = await _getDeviceId();
      _finalSetup(deviceId, parentUid);
    } else {
      debugPrint('//TEST: Pairing FAILED for code: $cleanCode');
      setState(() => _status = 'Invalid or expired code');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _status = 'Device Unpaired');
      });
    }
  }

  Future<String> _getDeviceId() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      final rawId = android.id;
      // Use 8-character uppercase code as the actual Firestore document ID
      return rawId.length > 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase();
    } catch (e) {
      debugPrint('//TEST: getDeviceId error: $e');
      // Fallback: use limited Firebase UID
      final fallback = FirebaseService.instance.currentUid ?? 'UNKNOWNID';
      return fallback.length > 8 ? fallback.substring(0, 8).toUpperCase() : fallback.toUpperCase();
    }
  }

  Future<void> _requestPermissions() async {
    // Location (always + background)
    final locationStatus = await Permission.location.request();
    debugPrint('//TEST: Location permission: $locationStatus');

    final bgLocationStatus = await Permission.locationAlways.request();
    debugPrint('//TEST: Background location: $bgLocationStatus');

    // Overlay (SYSTEM_ALERT_WINDOW) - CRITICAL for native overlay
    final overlayStatus = await Permission.systemAlertWindow.request();
    debugPrint('//TEST: Overlay permission: $overlayStatus');

    // Notification
    final notifStatus = await Permission.notification.request();
    debugPrint('//TEST: Notification permission: $notifStatus');

    // Battery optimization (ignore for background)
    final batteryStatus = await Permission.ignoreBatteryOptimizations.request();
    debugPrint('//TEST: Battery optimization: $batteryStatus');

    // Camera for scanner
    final cameraStatus = await Permission.camera.request();
    debugPrint('//TEST: Camera permission: $cameraStatus');

    // Phone — needed for emergency calls from lock screen
    final phoneStatus = await Permission.phone.request();
    debugPrint('//TEST: Phone permission: $phoneStatus');

    // Usage Stats - only open settings if NOT already granted
    await _requestUsageStatsIfNeeded();
  }

  Future<void> _requestUsageStatsIfNeeded() async {
    try {
      // Check first — don't open settings if already granted
      final hasPermission =
          await _platform.invokeMethod<bool>('hasUsagePermission') ?? false;
      if (!hasPermission) {
        debugPrint('//TEST: Usage Stats NOT granted — opening settings');
        await _platform.invokeMethod('requestUsageStatsPermission');
      } else {
        debugPrint('//TEST: Usage Stats already granted — skipping settings');
      }
    } catch (e) {
      debugPrint('//TEST: _requestUsageStatsIfNeeded error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color yellowBg = Color(0xFFFBC02D); // Vibrant Yellow
    const Color lightYellowCard = Color(0xFFFFE082); // Light yellow card
    const Color blueAccent = Color(0xFF3B82F6); // Blue color for borders and buttons

    return Scaffold(
      backgroundColor: yellowBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Key Icon Circle
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: blueAccent, width: 8),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.vpn_key_rounded,
                            color: Colors.orange, size: 56),
                        Positioned(
                          top: 25,
                          right: 25,
                          child: Icon(Icons.vpn_key_rounded,
                              color: Colors.orangeAccent.shade400, size: 36),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  const Text(
                    'CONNECT',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),

                  const SizedBox(height: 8),

                  if (_status != 'Device Unpaired' && _status != 'Invalid or expired code' && _initialized)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Text(
                        _status,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                  if (!_initialized)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: CircularProgressIndicator(color: Colors.black),
                    ),

                  if (_status == 'Device Unpaired' ||
                      _status == 'Invalid or expired code') ...[
                    const SizedBox(height: 24),
                    
                    const Text(
                      'Enter PIN Code',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Code Input Field
                    Container(
                      height: 60,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.transparent, // Background removed
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black, width: 1.0),
                      ),
                      child: Center(
                        child: TextField(
                          onChanged: (v) {
                            if (v.length == 6) _pairWithCode(v);
                          },
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          obscureText: false,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 16,
                          ),
                          decoration: const InputDecoration(
                            hintText: '* * * * * *',
                            hintStyle: TextStyle(
                              color: Colors.black38,
                              fontSize: 24,
                              letterSpacing: 8,
                            ),
                            counterText: '',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  const Text(
                    'Or',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // SCAN QR Button (Blue)
                  GestureDetector(
                    onTap: _startQRScan,
                    child: Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        color: blueAccent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          SizedBox(width: 16),
                          Text(
                            'Scan QR Code',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (_initialized && _status == 'Ready!') ...[
                  const SizedBox(height: 20),
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 48),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
 }
}
