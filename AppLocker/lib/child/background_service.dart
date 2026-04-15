// lib/child/background_service.dart
// WorkManager background tasks:
//   1. Every 15 min: GPS + battery → Firestore
//   2. Every 30 sec: Poll Firestore lock state → show/hide overlay
//   3. FCM listener: process commands
//
// TEST: adb shell dumpsys jobscheduler | grep parental
// TEST: Check Firestore Console for lat/lng/battery updates every 15min

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../shared/firebase_service.dart';
import '../shared/models/device_model.dart';

// ─── Task Names ───────────────────────────────────────────────────────────────

const _kLocationBatteryTask = 'locationBatteryTask';
const _kHeartbeatTask = 'heartbeatTask';
const _kIsolateName = 'childBackground';

// Platform channel for overlay / lock task control
const _lockChannel = MethodChannel('com.parentalcontrol/lock');

// ─── WorkManager Callback ─────────────────────────────────────────────────────

/// Called by WorkManager in background isolate
/// Must be a top-level function annotated with @pragma
@pragma('vm:entry-point')
void workManagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      debugPrint('//TEST: WorkManager task: $taskName');

      // Ensure Firebase is initialized in this isolate
      await Firebase.initializeApp();

      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('deviceId') ?? '';

      if (deviceId.isEmpty) {
        debugPrint('//TEST: No deviceId in prefs — skipping task');
        return true;
      }

      switch (taskName) {
        case _kLocationBatteryTask:
          await _runLocationBatteryTask(deviceId);
          break;
        case _kHeartbeatTask:
          await _runHeartbeatTask(deviceId);
          break;
        default:
          debugPrint('//TEST: Unknown task: $taskName');
      }

      return true; // Signal success to WorkManager
    } catch (e) {
      debugPrint('//TEST: WorkManager task error ($taskName): $e');
      return true; // Return true to avoid retry loop
    }
  });
}

// ─── Location + Battery Task (every 15 min) ───────────────────────────────────

Future<void> _runLocationBatteryTask(String deviceId) async {
  debugPrint('//TEST: Running location+battery task for $deviceId');

  double? lat;
  double? lng;
  int? battery;

  // Get location
  try {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      lat = position.latitude;
      lng = position.longitude;
      debugPrint('//TEST: GPS: $lat, $lng');
    } else {
      debugPrint('//TEST: Location permission denied');
    }
  } catch (e) {
    debugPrint('//TEST: GPS error: $e');
  }

  // Get battery level
  try {
    final bat = Battery();
    battery = await bat.batteryLevel;
    debugPrint('//TEST: Battery: $battery%');
  } catch (e) {
    debugPrint('//TEST: Battery error: $e');
  }

  // Update Firestore
  await FirebaseService.instance.updateDeviceData(
    deviceId: deviceId,
    lat: lat,
    lng: lng,
    battery: battery,
    status: 'online',
  );

  // Notify foreground isolate via port
  _sendToForeground({'type': 'locationUpdate', 'lat': lat, 'lng': lng, 'battery': battery});
}

// ─── Heartbeat Task (poll lock state every 30s) ───────────────────────────────

Future<void> _runHeartbeatTask(String deviceId) async {
  debugPrint('//TEST: Running heartbeat task for $deviceId');
  try {
    // Update heartbeat timestamp in Firestore
    await FirebaseService.instance.updateHeartbeat(deviceId);

    // Fetch the full Firestore doc to get lock schedules + manual lock state + controlMode
    final doc = await FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId)
        .get();

    if (!doc.exists) {
      debugPrint('//TEST: Heartbeat: device doc not found');
      return;
    }

    final device = DeviceModel.fromDoc(doc);
    final shouldLock = device.shouldBeLocked;

    debugPrint(
        '//TEST: Heartbeat: manual=${device.locked} mode=${device.controlMode} → shouldLock=$shouldLock');

    _sendToForeground({
      'type': 'lockState', 
      'locked': shouldLock, 
      'controlMode': device.controlMode,
      'hiddenApps': device.hiddenApps,
    });
  } catch (e) {
    debugPrint('//TEST: Heartbeat error: $e');
  }
}

// ─── Isolate Communication ────────────────────────────────────────────────────

void _sendToForeground(Map<String, dynamic> message) {
  try {
    final port = IsolateNameServer.lookupPortByName(_kIsolateName);
    port?.send(message);
  } catch (e) {
    debugPrint('//TEST: sendToForeground error: $e');
  }
}

// ─── ChildBackgroundService ───────────────────────────────────────────────────

class ChildBackgroundService {
  static Timer? _heartbeatTimer;
  static ReceivePort? _port;
  static StreamController<Map<String, dynamic>>? _eventController;

  static Stream<Map<String, dynamic>> get events =>
      _eventController?.stream ?? const Stream.empty();

  /// Initialize WorkManager + register tasks
  static Future<void> initialize({required String deviceId}) async {
    try {
      // Setup event stream
      _eventController = StreamController<Map<String, dynamic>>.broadcast();

      // Register isolate port for background -> foreground comms
      _port = ReceivePort();
      IsolateNameServer.removePortNameMapping(_kIsolateName);
      IsolateNameServer.registerPortWithName(_port!.sendPort, _kIsolateName);
      _port!.listen((message) {
        debugPrint('//TEST: Foreground received: $message');
        _eventController?.add(message as Map<String, dynamic>);
      });

      // Initialize WorkManager
      await Workmanager().initialize(
        workManagerCallbackDispatcher,
        isInDebugMode: false,
      );

      // Task 1: Location + Battery every 15 minutes
      await Workmanager().registerPeriodicTask(
        _kLocationBatteryTask,
        _kLocationBatteryTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
      debugPrint('//TEST: WorkManager: locationBattery task registered (15min)');

      // Task 2: Start in-app heartbeat timer (30s poll)
      _startHeartbeatTimer(deviceId);

      debugPrint('//TEST: Background service initialized for $deviceId');
    } catch (e) {
      debugPrint('//TEST: Background service init error: $e');
    }
  }

  /// 30-second Firestore poll for lock state (in-app timer)
  static void _startHeartbeatTimer(String deviceId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final doc = await FirebaseFirestore.instance.collection('devices').doc(deviceId).get();
        if (doc.exists) {
          final device = DeviceModel.fromDoc(doc);
          debugPrint('//TEST: Heartbeat timer: locked=${device.locked}, mode=${device.controlMode}');
          _eventController?.add({
             'type': 'lockState', 
             'locked': device.shouldBeLocked,
             'controlMode': device.controlMode,
             'hiddenApps': device.hiddenApps,
          });
          // Also update heartbeat from foreground while app is open
          FirebaseService.instance.updateHeartbeat(deviceId);
        }
      } catch (e) {
        debugPrint('//TEST: Heartbeat timer error: $e');
      }
    });
    debugPrint('//TEST: Heartbeat timer started (30s interval)');
  }

  /// Cancel all background tasks (call on uninstall/logout)
  static Future<void> cancelAll() async {
    try {
      _heartbeatTimer?.cancel();
      await Workmanager().cancelAll();
      _port?.close();
      IsolateNameServer.removePortNameMapping(_kIsolateName);
      await _eventController?.close();
      debugPrint('//TEST: All background tasks cancelled');
    } catch (e) {
      debugPrint('//TEST: cancelAll error: $e');
    }
  }
}
