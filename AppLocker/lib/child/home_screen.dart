// lib/child/home_screen.dart
// Child home screen — shows device status, lock state, device ID
// Listens to Firestore real-time + background service events
//
// TEST: Send 'show_overlay' command from dashboard → overlay appears on this screen
// TEST: Enter PIN "1234" → overlay dismisses, this screen re-appears

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_device_apps/flutter_device_apps.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../shared/firebase_service.dart';
import '../shared/models/device_model.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'lock_overlay.dart';
import 'background_service.dart';
import 'main_child.dart';

class ChildHomeScreen extends StatefulWidget {
  final String deviceId;

  const ChildHomeScreen({super.key, required this.deviceId});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> {
  String _appVersion = 'v2.0.0+11';
  bool _locked = false;
  int _battery = 0;
  double _lat = 0;
  double _lng = 0;
  String _status = 'Online';
  StreamSubscription? _firestoreSubscription;
  StreamSubscription? _bgSubscription;
  StreamSubscription? _lockControllerSubscription;
  String _pairingCode = '';
  String _pin = '1234';
  List<String> _taskList = [];
  String _taskTitle = "Mother's To-Do List";
  String _warningTitle = "Restricted Access";
  List<String> _warningList = [];
  List<String> _lastHiddenApps = [];
  List<String> _currentHiddenApps = [];
  String _lastControlMode = 'basic';
  Timer? _scheduleTimer;
  bool _hasUsagePermission = true;
  bool _isAdminActive = true;
  bool _hasAccessibilityPermission = true;
  bool _hasNotificationPermission = true;
  String? _blockedApp; // When not null, show the 'BlockedAppOverlay'
  String _lockHeadline = 'LOCKED';
  String _restrictedHeadline = 'APP RESTRICTED';
  String _lockMessage = 'This device is temporarily locked.\nComplete the tasks or enter PIN to unlock.';
  String _restrictedMessage = 'Access to this application is restricted.';
  String _parentQuote = '';
  String _profileImageUrl = '';
  String _unlockGreeting = 'Enjoy Your Day';
  Timer? _permissionCheckTimer;

  static const _lockChannel = MethodChannel('com.parentalcontrol/lock');
  bool _installedAppsSynced = false;
  Timer? _nativeOverlayCheckTimer;
  Timer? _appListSyncRetryTimer;
  // Permissions start as "true" (assumed granted) to avoid flashing the
  // warning card on launch before the OS has had time to respond.
  // They are updated after a 2-second settling delay.
  bool _permissionsSettled = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = 'v${info.version}+${info.buildNumber}');
      _checkForUpdates(info);
    });
    _listenToFirestore();
    _listenToBackgroundEvents();
    _listenToLockController();
    _listenToNativeChannel(); // Added listener for native app blocks
    _loadDeviceInfo();
    _checkUsagePermission();
    _checkAdminPermission();
    _startNativeBackgroundService(); // Start native Firestore poller
    // Check if we were brought to foreground due to a blocked app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForBlockedAppIntent();
      // Restore local settings if needed
      _restoreLocalSettings();
    });
    // Set deviceId on global controller
    ChildLockController.instance.setDeviceId(widget.deviceId);
    // Delay permission checks by 2 s so ColorOS/OPPO has time to report
    // the correct state. Avoids the false-positive Usage Access screen.
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _checkUsagePermission();
      _checkAdminPermission();
      setState(() => _permissionsSettled = true);
      // After settled, re-check every 5 seconds (no need for 1.5 s polling)
      _permissionCheckTimer =
          Timer.periodic(const Duration(seconds: 5), (_) {
        _checkUsagePermission();
        _checkAdminPermission();
        _checkAccessibilityPermission();
        _checkNotificationPermission();
      });
    });
    // Re-evaluate schedule every 30 seconds locally
    _scheduleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkSchedule();
    });
    // Check if native overlay unlocked the device (every 2s)
    _nativeOverlayCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkNativeOverlayState();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted || _installedAppsSynced) return;
        _trySyncInstalledApps(reason: 'post-frame');
      });
    });
    _appListSyncRetryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _installedAppsSynced) {
        _appListSyncRetryTimer?.cancel();
        return;
      }
      _trySyncInstalledApps(reason: 'periodic');
    });
  }

  void _listenToNativeChannel() {
    _lockChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAppBlocked') {
        final pkg = call.arguments['packageName'] as String?;
        debugPrint('//TEST: Native notified app block: $pkg');
        if (pkg != null && mounted) {
          setState(() => _blockedApp = pkg);
        }
      }
    });
  }

  @override
  void dispose() {
    _firestoreSubscription?.cancel();
    _bgSubscription?.cancel();
    _lockControllerSubscription?.cancel();
    _scheduleTimer?.cancel();
    _permissionCheckTimer?.cancel();
    _nativeOverlayCheckTimer?.cancel();
    _appListSyncRetryTimer?.cancel();
    super.dispose();
  }

  /// Start the native background service that polls Firestore independently
  Future<void> _startNativeBackgroundService() async {
    try {
      await _lockChannel.invokeMethod('startBackgroundService', {
        'deviceId': widget.deviceId,
        'pin': _pin,
      });
      debugPrint(
          '//TEST: Native background service started for ${widget.deviceId}');
    } catch (e) {
      debugPrint('//TEST: _startNativeBackgroundService error: $e');
    }
  }

  /// Check if the native overlay was dismissed (PIN entered on native side)
  Future<void> _checkNativeOverlayState() async {
    try {
      final isShowing =
          await _lockChannel.invokeMethod<bool>('isNativeOverlayShowing') ??
              false;
      // If we think we're locked but native overlay is gone, sync the unlock
      if (_locked && !isShowing) {
        debugPrint(
            '//TEST: Native overlay dismissed externally, syncing unlock');
        ChildLockController.instance.unlock();
        setState(() => _locked = false);
      }
    } catch (e) {
      // Method might not be available, ignore
    }
  }

  /// Checks if current time falls in a schedule and locks/unlocks accordingly
  Future<void> _checkSchedule() async {
    try {
      final doc =
          await FirebaseService.instance.streamDevice(widget.deviceId).first;
      if (!doc.exists) return;
      final device =
          DeviceModel.fromDoc(doc as DocumentSnapshot<Map<String, dynamic>>);
      final shouldLock = device.shouldBeLocked;
      if (shouldLock && !_locked) {
        debugPrint('//TEST: Schedule timer triggered lock');
        ChildLockController.instance.lock();
      } else if (!shouldLock && _locked && !device.locked) {
        debugPrint('//TEST: Schedule timer triggered unlock');
        ChildLockController.instance.unlock();
      }
    } catch (e) {
      debugPrint('//TEST: _checkSchedule error: $e');
    }
  }

  Future<void> _checkUsagePermission() async {
    try {
      const channel = MethodChannel('com.parentalcontrol/lock');
      final has = await channel.invokeMethod<bool>('hasUsagePermission') ?? false;
      if (mounted && _hasUsagePermission != has) {
        setState(() => _hasUsagePermission = has);
        if (has) debugPrint('//TEST: Usage Permission GRANTED');
      }
      // Also sync deviceId to local shared prefs for native services
      final lPrefs = await SharedPreferences.getInstance();
      final devId = lPrefs.getString('deviceId') ?? '';
      if (devId.isNotEmpty) {
        await channel.invokeMethod('startBackgroundService', {
          'deviceId': devId,
          'pin': _pin,
        });
      }
    } catch (e) {
      debugPrint('//TEST: _checkUsagePermission error: $e');
    }
  }

  Future<void> _checkAdminPermission() async {
    try {
      const channel = MethodChannel('com.parentalcontrol/lock');
      final active = await channel.invokeMethod<bool>('isAdminActive') ?? false;
      if (mounted && _isAdminActive != active) {
        setState(() => _isAdminActive = active);
        if (active) debugPrint('//TEST: Admin Permission GRANTED');
      }
    } catch (e) {
      debugPrint('//TEST: _checkAdminPermission error: $e');
    }
  }

  Future<void> _checkAccessibilityPermission() async {
    try {
      final has = await _lockChannel.invokeMethod<bool>('hasAccessibilityPermission') ?? false;
      if (mounted && _hasAccessibilityPermission != has) {
        setState(() => _hasAccessibilityPermission = has);
      }
    } catch (e) {
      debugPrint('//TEST: _checkAccessibilityPermission error: $e');
    }
  }

  Future<void> _checkNotificationPermission() async {
    try {
      final has = await _lockChannel.invokeMethod<bool>('hasNotificationPermission') ?? false;
      if (mounted && _hasNotificationPermission != has) {
        setState(() => _hasNotificationPermission = has);
      }
    } catch (e) {
      debugPrint('//TEST: _checkNotificationPermission error: $e');
    }
  }

  Future<void> _requestUsagePermission() async {
    try {
      const channel = MethodChannel('com.parentalcontrol/lock');
      await channel.invokeMethod('requestUsagePermission');
    } catch (e) {
      debugPrint('//TEST: _requestUsagePermission error: $e');
    }
  }

  Future<void> _requestAdminPermission() async {
    try {
      const channel = MethodChannel('com.parentalcontrol/lock');
      await channel.invokeMethod('requestAdminPermission');
    } catch (e) {
      debugPrint('//TEST: _requestAdminPermission error: $e');
    }
  }

  Future<void> _requestAccessibilityPermission() async {
    try {
      await _lockChannel.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      debugPrint('//TEST: _requestAccessibilityPermission error: $e');
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await _lockChannel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      debugPrint('//TEST: _requestNotificationPermission error: $e');
    }
  }

  /// Returns true if a non-empty app list was written to Firestore.
  /// Returns false if nothing to upload yet (retries can continue).
  Future<bool> _syncInstalledApps() async {
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        debugPrint('//TEST: _syncInstalledApps cannot sign in: $e');
        rethrow;
      }
    }
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError(
          'No Firebase user; enable Anonymous sign-in in Firebase Console');
    }

    final List<Map<String, dynamic>> apps = [];
    final List<AppInfo> installedApps = await FlutterDeviceApps.listApps(
      includeSystem: true,
      onlyLaunchable: true,
      includeIcons: false, // CRITICAL: NEVER INCLUDE ICONS. Base64 lists exceed 2MB SQLite limit and crash Firestore!
    );

    debugPrint(
        '//TEST: FlutterDeviceApps.listApps → ${installedApps.length} apps');

    for (final app in installedApps) {
      final pkg = app.packageName;
      if (pkg == null || pkg.isEmpty) continue;
      apps.add({
        'name': app.appName ?? pkg,
        'packageName': pkg,
        // Removed 'iconBase64' entirely
        if (app.category != null) 'category': app.category.toString(),
      });
    }

    if (apps.isEmpty) {
      try {
        final dynamic raw =
            await _lockChannel.invokeMethod('listLaunchableApps');
        if (raw is List) {
          for (final e in raw) {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              final pkg = m['packageName']?.toString();
              if (pkg == null || pkg.isEmpty) continue;
              apps.add({
                'name': m['name']?.toString() ?? pkg,
                'packageName': pkg,
              });
            }
          }
        }
        debugPrint('//TEST: Native listLaunchableApps → ${apps.length} apps');
      } catch (e) {
        debugPrint('//TEST: listLaunchableApps native fallback error: $e');
      }
    }

    if (apps.isEmpty) {
      debugPrint(
          '//TEST: _syncInstalledApps: no apps (plugin + native empty?)');
      return false;
    }

    debugPrint('//TEST: Syncing ${apps.length} apps to Firestore...');
    await FirebaseService.instance.updateInstalledApps(widget.deviceId, apps);
    debugPrint('//TEST: App sync COMPLETED successfully');
    return true;
  }

  void _trySyncInstalledApps({required String reason}) {
    if (_installedAppsSynced) return;
    _syncInstalledApps().then((ok) {
      if (mounted && ok) setState(() => _installedAppsSynced = true);
    }).catchError((e) {
      debugPrint('//TEST: installed apps sync ($reason) failed: $e');
    });
  }

  void _listenToFirestore() {
    _firestoreSubscription = FirebaseService.instance
        .streamDevice(widget.deviceId)
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final DeviceModel device;
      try {
        device = DeviceModel.fromDoc(
            snapshot as DocumentSnapshot<Map<String, dynamic>>);
      } catch (e, st) {
        debugPrint('//TEST: DeviceModel.fromDoc failed: $e\n$st');
        return;
      }

      if (mounted) {
        setState(() {
          _battery = device.battery;
          _lat = device.lat;
          _lng = device.lng;
          _status = device.status;
          _pin = device.pin;
          _taskList = device.taskList;
          _taskTitle = device.taskTitle;
          _warningTitle = device.warningTitle;
          _warningList = device.warningList;
          _currentHiddenApps = device.hiddenApps;
          _lockHeadline = device.lockHeadline;
          _restrictedHeadline = device.restrictedHeadline;
          _lockMessage = device.lockMessage;
          _restrictedMessage = device.restrictedMessage;
          _parentQuote = device.parentQuote;
          _profileImageUrl = device.profileImageUrl;
          _unlockGreeting = device.unlockGreeting;
        });

        // Update PIN and profile image on the lock controller (passed to native overlay)
        ChildLockController.instance.setPin(device.pin);
        ChildLockController.instance.setProfileImageUrl(device.profileImageUrl);

        _syncHiddenApps(device); // Pass the whole device for mode/access checks
        _syncToNativeService(device.blockedApps);

        // First successful sync per session (retries if Firestore write failed previously).
        if (!_installedAppsSynced) {
          _syncInstalledApps().then((ok) {
            if (mounted && ok) setState(() => _installedAppsSynced = true);
          }).catchError((e) {
            debugPrint('//TEST: installed apps sync will retry: $e');
          });
        }

        // Handle pending commands from Firestore
        if (device.pendingCommand != null) {
          _handleCommand(device.pendingCommand!);
          FirebaseService.instance.clearPendingCommand(widget.deviceId);
        }

        // Sync lock state
        final shouldLock = device.shouldBeLocked;
        if (shouldLock && !_locked) {
          _handleCommand('show_overlay'); // Use handleCommand to force popup
        } else if (!shouldLock && _locked) {
          ChildLockController.instance.unlock();
        }
      }
    }, onError: (e) {
      debugPrint('//TEST: Firestore stream error: $e');
    });
  }

  void _listenToBackgroundEvents() {
    _bgSubscription = ChildBackgroundService.events.listen((event) {
      if (!mounted) return;
      if (event['type'] == 'lockState') {
        final locked = event['locked'] as bool? ?? false;
        if (locked && !_locked) {
          ChildLockController.instance.lock();
        } else if (!locked && _locked) {
          ChildLockController.instance.unlock();
        }
      } else if (event['type'] == 'locationUpdate') {
        setState(() {
          _lat = (event['lat'] as num?)?.toDouble() ?? _lat;
          _lng = (event['lng'] as num?)?.toDouble() ?? _lng;
          _battery = event['battery'] as int? ?? _battery;
        });
      }
    });
  }

  void _listenToLockController() {
    _lockControllerSubscription = ChildLockController.instance.addListener(() {
      if (mounted) {
        setState(() => _locked = ChildLockController.instance.locked);
      }
    }) as StreamSubscription?;
  }

  void _handleCommand(String command) {
    switch (command) {
      case 'show_overlay':
        ChildLockController.instance.lock();
        break;
      case 'hide_overlay':
      case 'force_unlock':
        ChildLockController.instance.unlock();
        break;
    }
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final bat = Battery();
      final level = await bat.batteryLevel;
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _battery = level;
          _lat = position.latitude;
          _lng = position.longitude;
          _pairingCode = widget.deviceId.length > 8
              ? widget.deviceId.substring(0, 8).toUpperCase()
              : widget.deviceId.toUpperCase();
        });
      }
      await FirebaseService.instance.updateDeviceData(
        deviceId: widget.deviceId,
        lat: position.latitude,
        lng: position.longitude,
        battery: level,
        status: 'online',
      );
    } catch (e) {
      debugPrint('//TEST: loadDeviceInfo error: $e');
    }
  }

  Future<void> _signOut() async {
    await ChildBackgroundService.cancelAll();
    await FirebaseService.instance.updateDeviceData(
      deviceId: widget.deviceId,
      status: 'offline',
    );
    await FirebaseService.instance.signOut();
  }

  Future<void> _copyDeviceId() async {
    await Clipboard.setData(ClipboardData(text: widget.deviceId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device ID copied to clipboard!')),
      );
    }
  }

  /// Syncs the blocked apps list, mode, and timed access to the native service
  Future<void> _syncToNativeService(List<String> apps) async {
    try {
      final doc =
          await FirebaseService.instance.streamDevice(widget.deviceId).first;
      if (!doc.exists) return;
      final device =
          DeviceModel.fromDoc(doc as DocumentSnapshot<Map<String, dynamic>>);

      const channel = MethodChannel('com.parentalcontrol/lock');

      // Convert Timestamp to milliseconds for Kotlin
      final Map<String, int> tempAccessMap = {};
      device.tempAccess.forEach((key, value) {
        if (value is Timestamp) {
          tempAccessMap[key] = value.millisecondsSinceEpoch;
        }
      });

      // Save settings locally first as backup
      await _saveLocalSettings(apps, device.controlMode, tempAccessMap, device.appSchedules);

      await channel.invokeMethod('syncBlockedApps', {
        'blockedApps': apps,
        'controlMode': device.controlMode,
        'tempAccess': tempAccessMap,
        'appSchedules': device.appSchedules,
      });
      debugPrint(
          '//TEST: Synced apps, mode(${device.controlMode}), schedules, and ${tempAccessMap.length} temp access to native');
    } catch (e) {
      debugPrint('//TEST: _syncToNativeService error: $e');
      // Fallback: try to restore from local settings
      await _restoreLocalSettings();
    }
  }

  Future<void> _saveLocalSettings(List<String> apps, String controlMode,
      Map<String, int> tempAccess, Map<String, dynamic> appSchedules) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('local_blocked_apps', apps);
      await prefs.setString('local_control_mode', controlMode);
      await prefs.setString('local_temp_access',
          tempAccess.entries.map((e) => '${e.key}:${e.value}').join(','));
      await prefs.setString('local_app_schedules',
          Uri.encodeComponent(jsonEncode(appSchedules)));
      await prefs.setString('local_device_id', widget.deviceId);
      await prefs.setString('local_pin', _pin);
      debugPrint('//TEST: Saved local settings backup');
    } catch (e) {
      debugPrint('//TEST: Failed to save local settings: $e');
    }
  }

  Future<void> _restoreLocalSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apps = prefs.getStringList('local_blocked_apps') ?? [];
      final controlMode = prefs.getString('local_control_mode') ?? 'basic';
      final tempAccessStr = prefs.getString('local_temp_access') ?? '';
      final deviceId = prefs.getString('local_device_id') ?? '';
      final pin = prefs.getString('local_pin') ?? '1234';
      final appSchedulesEncoded = prefs.getString('local_app_schedules') ?? '';

      if (apps.isNotEmpty && deviceId.isNotEmpty) {
        final Map<String, int> tempAccessMap = {};
        if (tempAccessStr.isNotEmpty) {
          final pairs = tempAccessStr.split(',');
          for (final pair in pairs) {
            final parts = pair.split(':');
            if (parts.length == 2) {
              tempAccessMap[parts[0]] = int.tryParse(parts[1]) ?? 0;
            }
          }
        }

        Map<String, dynamic> appSchedules = {};
        if (appSchedulesEncoded.isNotEmpty) {
          try {
            appSchedules = Map<String, dynamic>.from(
                jsonDecode(Uri.decodeComponent(appSchedulesEncoded)));
          } catch (_) {}
        }

        const channel = MethodChannel('com.parentalcontrol/lock');
        await channel.invokeMethod('syncBlockedApps', {
          'blockedApps': apps,
          'controlMode': controlMode,
          'tempAccess': tempAccessMap,
          'appSchedules': appSchedules,
        });
        debugPrint('//TEST: Restored settings from local backup');
      }
    } catch (e) {
      debugPrint('//TEST: Failed to restore local settings: $e');
    }
  }


  Future<void> _syncHiddenApps(DeviceModel device) async {
    final currentHiddenApps = device.hiddenApps;
    final set1 = Set.from(_lastHiddenApps);
    final set2 = Set.from(currentHiddenApps);
    final modeChanged = _lastControlMode != device.controlMode;

    // Check for changes or mode change
    if (!modeChanged && set1.length == set2.length && set1.containsAll(set2))
      return;

    final isAdvanced = device.controlMode == 'advanced';

    for (final pkg in _lastHiddenApps) {
      if (!currentHiddenApps.contains(pkg)) {
        await _setAppHiddenNative(pkg, false);
      }
    }

    for (final pkg in currentHiddenApps) {
      // Skip hiding if "Timed Access" is active
      final expiry = device.tempAccess[pkg] as Timestamp?;
      bool hasAccess = false;
      if (expiry != null && expiry.toDate().isAfter(DateTime.now())) {
        hasAccess = true;
      }

      // Only hide if in Advanced Mode AND no active temp access
      await _setAppHiddenNative(pkg, isAdvanced && !hasAccess);
    }
    _lastHiddenApps = List.from(currentHiddenApps);
    _lastControlMode = device.controlMode;
  }

  Future<void> _checkForBlockedAppIntent() async {
    try {
      const channel = MethodChannel('com.parentalcontrol/lock');
      final blockedPackage = await channel.invokeMethod('getBlockedPackage');
      if (blockedPackage != null && blockedPackage.toString().isNotEmpty) {
        debugPrint('//TEST: Blocked app from Intent: $blockedPackage');
        setState(() => _blockedApp = blockedPackage.toString());
        // Clear the Intent extra after handling
        await channel.invokeMethod('clearBlockedPackage');
      }
    } catch (e) {
      debugPrint('//TEST: Error checking blocked app Intent: $e');
    }
  }

  Future<void> _setAppHiddenNative(String packageName, bool hidden) async {
    try {
      const channel = MethodChannel('com.parentalcontrol/lock');
      // Fetch activity for the package (needed for disabling component)
      String? activity;
      try {
        final info = await FlutterDeviceApps.getApp(packageName);
      } catch (_) {}

      await channel.invokeMethod('setApplicationHidden', {
        'packageName': packageName,
        'hidden': hidden,
      });
    } catch (e) {
      debugPrint('//TEST: Native setApplicationHidden error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return LockOverlay(
        deviceId: widget.deviceId,
        pin: _pin,
        todos: _taskList,
        lockTitle: _taskTitle,
        headline: _lockHeadline,
        fallbackMessage: _lockMessage,
        onUnlock: () async {
          ChildLockController.instance.unlock();
          await FirebaseService.instance.updateDeviceData(
            deviceId: widget.deviceId,
            locked: false,
          );
        },
      );
    }

    // Show blocked app using the lock overlay UI as a full-screen cover
    if (_blockedApp != null) {
      return LockOverlay(
        deviceId: widget.deviceId,
        pin: _pin,
        headline: _restrictedHeadline,
        todos: _warningList,
        lockTitle: _warningTitle,
        fallbackMessage: _restrictedMessage,
        onUnlock: () {
          setState(() => _blockedApp = null);
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        shadowColor: Colors.black12,
        title: Row(
          children: [
            GestureDetector(
              onLongPress: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('DEV RESET: SharedPreferences Wiped! Restart App!')),
                  );
                }
              },
              child: const Text(
                'AppLocker',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onLongPress: () async {
                try {
                  const channel = MethodChannel('com.parentalcontrol/lock');
                  final unhiddenCount = await channel.invokeMethod<int>('unhideAllPkgs') ?? 0;
                  _installedAppsSynced = false;
                  _trySyncInstalledApps(reason: 'rescued hidden apps');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('DEV RESCUE: $unhiddenCount missing apps restored!')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('RESCUE FAILED: $e')),
                    );
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _appVersion,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.sync_rounded, color: Colors.grey.shade600, size: 22),
            onPressed: () async {
              final info = await PackageInfo.fromPlatform();
              _checkForUpdates(info, manual: true);
            },
            tooltip: 'Check for Updates',
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: Colors.grey.shade600, size: 22),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_permissionsSettled &&
                (!_hasUsagePermission ||
                    !_isAdminActive ||
                    !_hasAccessibilityPermission ||
                    !_hasNotificationPermission))
              _buildPermissionCard(),
            const SizedBox(height: 4),
            _buildStatusRow(),
            const SizedBox(height: 12),
            _buildQuoteCard(),
            const SizedBox(height: 12),
            _buildUnlockCard(),
            const SizedBox(height: 12),
            _buildPairingSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow() {
    Color batteryColor;
    IconData batteryIcon;
    if (_battery >= 50) {
      batteryColor = const Color(0xFF10B981);
      batteryIcon = Icons.battery_full_rounded;
    } else if (_battery >= 20) {
      batteryColor = const Color(0xFFF59E0B);
      batteryIcon = Icons.battery_5_bar_rounded;
    } else {
      batteryColor = const Color(0xFFEF4444);
      batteryIcon = Icons.battery_alert_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEFF8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _status.toLowerCase() == 'online'
                  ? const Color(0xFF22C55E)
                  : Colors.grey,
            ),
            child: Icon(
              _status.toLowerCase() == 'online'
                  ? Icons.check_rounded
                  : Icons.wifi_off_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _status.toLowerCase() == 'online' ? 'Online' : 'Offline',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Color(0xFF374151),
            ),
          ),
          const Spacer(),
          Icon(batteryIcon, color: batteryColor, size: 30),
          const SizedBox(width: 6),
          Text(
            '$_battery%',
            style: TextStyle(
              color: batteryColor,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEFF8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: '♥',
                        style: TextStyle(
                          fontSize: 26,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      TextSpan(
                        text: ' ~',
                        style: TextStyle(
                          fontSize: 22,
                          color: Color(0xFFEF4444),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _parentQuote.isNotEmpty
                      ? '" $_parentQuote"'
                      : '" Have a wonderful day!"',
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 110,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF22C55E), width: 2.5),
              color: const Color(0xFFD1FAE5),
            ),
            clipBehavior: Clip.hardEdge,
            child: _profileImageUrl.isNotEmpty
                ? Image.network(
                    _profileImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF22C55E),
                      size: 50,
                    ),
                  )
                : const Icon(
                    Icons.person_rounded,
                    color: Color(0xFF22C55E),
                    size: 50,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEFF8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: const Center(
              child: Icon(Icons.lock_open_rounded,
                  color: Color(0xFF22C55E), size: 34),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Device Unlocked',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '"$_unlockGreeting"',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF374151),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairingSection() {
    return GestureDetector(
      onTap: _copyDeviceId,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9F8),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.qr_code_rounded, color: Colors.black38, size: 20),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pairing Code',
                  style: TextStyle(
                      fontSize: 11, color: Colors.black38, letterSpacing: 0.5),
                ),
                Text(
                  _pairingCode.isNotEmpty ? _pairingCode : '——',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.copy_rounded, color: Colors.black26, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard() {
    Widget _permRow(String label, String btnLabel, Color btnColor, VoidCallback onTap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(backgroundColor: btnColor, foregroundColor: Colors.white, elevation: 0),
              child: Text(btnLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 12),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber),
              SizedBox(width: 12),
              Expanded(child: Text('Setup Required', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.amber, fontSize: 15))),
            ],
          ),
          const SizedBox(height: 14),
          if (!_hasUsagePermission)
            _permRow('• Usage Access (track app usage)', 'FIX USAGE ACCESS', Colors.amber.shade700, _requestUsagePermission),
          if (!_isAdminActive)
            _permRow('• Device Admin (prevent uninstallation)', 'ACTIVATE DEVICE ADMIN', Colors.black87, _requestAdminPermission),
          if (!_hasAccessibilityPermission)
            _permRow('• Accessibility (monitor apps & URLs)', 'ENABLE ACCESSIBILITY', Colors.orange.shade700, _requestAccessibilityPermission),
          if (!_hasNotificationPermission)
            _permRow('• Notification Access (monitor messages)', 'ENABLE NOTIFICATIONS', Colors.deepOrange, _requestNotificationPermission),
          Text(
            'Tap each button above, then come back here once done.',
            style: TextStyle(fontSize: 11, color: Colors.amber.withOpacity(0.7), fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdates(PackageInfo info, {bool manual = false}) async {
    try {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checking for updates...')),
        );
      }
      
      final doc = await FirebaseFirestore.instance.collection('config').doc('appUpdates').get();
      if (!doc.exists) {
        if (manual) _showNoUpdatesAlert();
        return;
      }

      final data = doc.data()!;
      final latestBuild = data['latestBuild'] as int? ?? 0;
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      if (latestBuild > currentBuild) {
        final latestVersion = data['latestVersion'] as String? ?? 'New Version';
        final updateLogs = data['updateLogs'] as String? ?? 'Bug fixes and improvements.';
        final downloadUrl = data['downloadUrl'] as String? ?? '';

        if (!mounted) return;
        _showUpdateDialog(latestVersion, updateLogs, downloadUrl);
      } else {
        if (manual) _showNoUpdatesAlert();
      }
    } catch (e) {
      debugPrint('//TEST: Check for updates failed: $e');
      if (manual) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking updates: $e')),
        );
      }
    }
  }

  void _showNoUpdatesAlert() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('Up to Date', style: TextStyle(color: Colors.white)),
        content: const Text('You are using the latest version of AppLocker.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(String version, String logs, String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: Text('Update Available: $version', style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("What's New:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(logs, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              const Text(
                "Note: After downloading, open the APK to install. It will automatically replace this app.",
                style: TextStyle(color: Colors.amber, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('LATER', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstall(url, version);
            },
            child: const Text('UPDATE NOW', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall(String url, String version) async {
    if (url.isEmpty) return;

    try {
      // Show progress overlay
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          backgroundColor: Color(0xFF1E1E2C),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Downloading update...", style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final dir = await getExternalStorageDirectory();
        final file = File('${dir!.path}/applocker_update_$version.apk');
        await file.writeAsBytes(response.bodyBytes);
        
        if (mounted) Navigator.pop(context); // Close progress dialog

        // Trigger install
        final result = await OpenFile.open(file.path);
        
        if (result.type != ResultType.done) {
          _showInstallError(file.path);
        }
      } else {
        throw "Download failed (code: ${response.statusCode})";
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close progress if still there
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  void _showInstallError(String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('Installation Required', style: TextStyle(color: Colors.white)),
        content: Text(
          "The update.apk was downloaded but could not be opened automatically.\n\n"
          "Please open your File Manager and install it from:\n$path",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }
}

// ─── Status Card ─────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final String deviceId;
  final String pairingCode;
  final int battery;
  final double lat;
  final double lng;
  final String status;
  final VoidCallback onCopyId;

  const _StatusCard({
    required this.deviceId,
    required this.pairingCode,
    required this.battery,
    required this.lat,
    required this.lng,
    required this.status,
    required this.onCopyId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D2D5F), Color(0xFF1A1A3E)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.2),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status == 'online' ? Colors.greenAccent : Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status == 'online' ? 'Online' : 'Offline',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const Spacer(),
              Icon(
                battery > 20 ? Icons.battery_full : Icons.battery_alert,
                color: battery > 20 ? Colors.greenAccent : Colors.redAccent,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                '$battery%',
                style: TextStyle(
                  color: battery > 20 ? Colors.greenAccent : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Device Pairing Code',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                pairingCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const Key('copy_device_id_btn'),
                icon: const Icon(Icons.copy, color: Colors.white54),
                onPressed: onCopyId,
                tooltip: 'Copy full Device ID',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Share this code to pair',
            style:
                TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.location_on,
                  color: Colors.deepPurpleAccent, size: 16),
              const SizedBox(width: 4),
              Text(
                lat != 0
                    ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                    : 'Location pending...',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Lock State Card ──────────────────────────────────────────────────────────

class _LockStateCard extends StatelessWidget {
  final bool locked;

  const _LockStateCard({required this.locked});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: locked
            ? Colors.red.withOpacity(0.15)
            : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: locked
              ? Colors.redAccent.withOpacity(0.5)
              : Colors.greenAccent.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            color: locked ? Colors.redAccent : Colors.greenAccent,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locked ? 'LOCKED BY PARENT' : 'Device Unlocked',
                  style: TextStyle(
                    color: locked ? Colors.redAccent : Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                  Text(
                    locked
                        ? 'Complete the tasks or enter PIN to unlock'
                        : 'Monitoring active — reporting every 15 min',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── To-Do List Card ────────────────────────────────────────────────────────
class _ToDoListCard extends StatelessWidget {
  final List<String> todos;
  final String lockTitle;
  const _ToDoListCard({required this.todos, required this.lockTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rounded,
                  color: Colors.deepPurpleAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                lockTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (todos.isEmpty)
            Text(
              "You have no tasks to do right now! 🎉",
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontStyle: FontStyle.italic),
            )
          else
            ...todos.map((task) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.check_circle_outline,
                            color: Colors.white.withOpacity(0.3), size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          task,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
