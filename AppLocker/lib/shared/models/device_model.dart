// lib/shared/models/device_model.dart
// Device data model mirroring Firestore /devices/{deviceId}

import 'package:cloud_firestore/cloud_firestore.dart';

/// A single time-based lock schedule block e.g. 07:01 → 08:00
class LockSchedule {
  final String start; // "HH:mm" 24-hour format e.g. "07:01"
  final String end;   // "HH:mm" 24-hour format e.g. "08:00"
  final bool enabled;

  const LockSchedule({
    required this.start,
    required this.end,
    this.enabled = true,
  });

  factory LockSchedule.fromMap(Map<String, dynamic> map) {
    return LockSchedule(
      start: map['start'] as String? ?? '00:00',
      end: map['end'] as String? ?? '00:00',
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'start': start,
        'end': end,
        'enabled': enabled,
      };

  /// Parse "HH:mm" into [hour, minute]
  static List<int> _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return [0, 0];
    return [int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0];
  }

  /// Returns true if [now] falls within this schedule block
  bool isActive(DateTime now) {
    if (!enabled) return false;
    final startParts = _parseTime(start);
    final endParts = _parseTime(end);
    final startMins = startParts[0] * 60 + startParts[1];
    final endMins = endParts[0] * 60 + endParts[1];
    final nowMins = now.hour * 60 + now.minute;

    // Handle overnight schedules e.g. 22:00 → 06:00
    if (endMins < startMins) {
      return nowMins >= startMins || nowMins < endMins;
    }
    return nowMins >= startMins && nowMins < endMins;
  }

  String get label => '$start – $end';
}

class DeviceModel {
  final String id;
  final String childUid;
  final String parentUid;
  final bool locked;
  final String status; // 'online' | 'offline'
  final double lat;
  final double lng;
  final int battery; // 0-100
  final String fcmToken;
  final DateTime? lastSeen;
  final String? pendingCommand;
  final List<LockSchedule> lockSchedules;
  final String pin;
  final List<String> taskList;
  final List<String> hiddenApps;
  final List<String> blockedApps;
  final String taskTitle;
  final String warningTitle;
  final List<String> warningList;
  final String lockHeadline;
  final String restrictedHeadline;
  final String lockMessage;
  final String restrictedMessage;
  final bool subscriptionActive;

  // Unlock page customisation
  final String parentQuote;
  final String profileImageUrl;
  final String unlockGreeting;

  // New Dashboard Features
  final String controlMode; // 'basic' | 'advanced'
  final Map<String, dynamic> tempAccess; // {pkgName: expiresAt}
  final List<Map<String, dynamic>> installedApps; // [{name, packageName, icon, activity}]
  final Map<String, dynamic> usageStats; // {date: {pkgName: seconds}}
  final Map<String, dynamic> appSchedules; // {pkgName: {start, end, alwaysBlocked}}

  const DeviceModel({
    required this.id,
    required this.childUid,
    required this.parentUid,
    required this.locked,
    required this.status,
    required this.lat,
    required this.lng,
    required this.battery,
    required this.fcmToken,
    this.lastSeen,
    this.pendingCommand,
    this.lockSchedules = const [],
    this.pin = '1234',
    this.taskList = const [],
    this.hiddenApps = const [],
    this.blockedApps = const [],
    this.taskTitle = 'Mother\'s To-Do List',
    this.warningTitle = 'Restricted Access',
    this.warningList = const [],
    this.controlMode = 'basic',
    this.tempAccess = const {},
    this.installedApps = const [],
    this.usageStats = const {},
    this.appSchedules = const {},
    this.lockHeadline = 'LOCKED',
    this.restrictedHeadline = 'APP RESTRICTED',
    this.lockMessage = 'This device is locked by your parent.\nPlease complete your routines to unlock.',
    this.restrictedMessage = 'Access to this application is restricted by parent settings.',
    this.subscriptionActive = true,
    this.parentQuote = '',
    this.profileImageUrl = '',
    this.unlockGreeting = 'Enjoy Your Day',
  });

  /// Firestore nested maps may be `Map<Object?, Object?>`; normalize for Dart.
  static List<Map<String, dynamic>> _installedAppsFromFirestore(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) {
        try {
          out.add(Map<String, dynamic>.from(e));
        } catch (_) {/* skip malformed row */}
      }
    }
    return out;
  }

  static List<LockSchedule> _lockSchedulesFromFirestore(dynamic raw) {
    if (raw is! List) return [];
    final out = <LockSchedule>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(LockSchedule.fromMap(Map<String, dynamic>.from(e)));
      } catch (_) {/* skip bad schedule entries */}
    }
    return out;
  }

  /// Parse from Firestore document snapshot
  factory DeviceModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return DeviceModel(
      id: doc.id,
      childUid: data['childUid'] as String? ?? '',
      parentUid: data['parentUid'] as String? ?? '',
      locked: data['locked'] as bool? ?? false,
      status: data['status'] as String? ?? 'offline',
      lat: (data['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (data['lng'] as num?)?.toDouble() ?? 0.0,
      battery: data['battery'] as int? ?? 0,
      fcmToken: data['fcmToken'] as String? ?? '',
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
      pendingCommand: data['pendingCommand'] as String?,
      pin: data['pin'] as String? ?? '1234',
      taskList: (data['taskList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? 
                (data['todos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      hiddenApps: (data['hiddenApps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      blockedApps: (data['blockedApps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      taskTitle: data['taskTitle'] as String? ?? data['lockTitle'] as String? ?? 'Mother\'s To-Do List',
      warningTitle: data['warningTitle'] as String? ?? 'Restricted Access',
      warningList: (data['warningList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      lockSchedules: _lockSchedulesFromFirestore(data['lockSchedules']),
      controlMode: data['controlMode'] as String? ?? 'basic',
      tempAccess: data['tempAccess'] is Map
          ? Map<String, dynamic>.from(data['tempAccess'] as Map)
          : {},
      installedApps: _installedAppsFromFirestore(data['installedApps']),
      usageStats: data['usageStats'] is Map
          ? Map<String, dynamic>.from(data['usageStats'] as Map)
          : {},
      appSchedules: data['appSchedules'] is Map
          ? Map<String, dynamic>.from(data['appSchedules'] as Map)
          : {},
      lockHeadline: data['lockHeadline'] as String? ?? 'LOCKED',
      restrictedHeadline: data['restrictedHeadline'] as String? ?? 'APP RESTRICTED',
      lockMessage: data['lockMessage'] as String? ?? 'This device is locked by your parent.\nPlease complete your routines to unlock.',
      restrictedMessage: data['restrictedMessage'] as String? ?? 'Access to this application is restricted by parent settings.',
      subscriptionActive: data['subscriptionActive'] as bool? ?? true,
      parentQuote: data['parentQuote'] as String? ?? '',
      profileImageUrl: data['profileImageUrl'] as String? ?? '',
      unlockGreeting: data['unlockGreeting'] as String? ?? 'Enjoy Your Day',
    );
  }

  /// Parse from raw map (e.g. WorkManager task data)
  factory DeviceModel.fromMap(Map<String, dynamic> map) {
    return DeviceModel(
      id: map['id'] as String? ?? '',
      childUid: map['childUid'] as String? ?? '',
      parentUid: map['parentUid'] as String? ?? '',
      locked: map['locked'] as bool? ?? false,
      status: map['status'] as String? ?? 'offline',
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      battery: map['battery'] as int? ?? 0,
      fcmToken: map['fcmToken'] as String? ?? '',
      pendingCommand: map['pendingCommand'] as String?,
      pin: map['pin'] as String? ?? '1234',
      taskList: (map['taskList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? 
                (map['todos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      hiddenApps: (map['hiddenApps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      blockedApps: (map['blockedApps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      taskTitle: map['taskTitle'] as String? ?? map['lockTitle'] as String? ?? 'Mother\'s To-Do List',
      warningTitle: map['warningTitle'] as String? ?? 'Restricted Access',
      warningList: (map['warningList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      lockSchedules: _lockSchedulesFromFirestore(map['lockSchedules']),
      controlMode: map['controlMode'] as String? ?? 'basic',
      tempAccess: map['tempAccess'] is Map
          ? Map<String, dynamic>.from(map['tempAccess'] as Map)
          : {},
      installedApps: _installedAppsFromFirestore(map['installedApps']),
      usageStats: map['usageStats'] is Map
          ? Map<String, dynamic>.from(map['usageStats'] as Map)
          : {},
      appSchedules: map['appSchedules'] is Map
          ? Map<String, dynamic>.from(map['appSchedules'] as Map)
          : {},
      lockHeadline: map['lockHeadline'] as String? ?? 'LOCKED',
      restrictedHeadline: map['restrictedHeadline'] as String? ?? 'APP RESTRICTED',
      lockMessage: map['lockMessage'] as String? ?? 'This device is locked by your parent.\nPlease complete your routines to unlock.',
      restrictedMessage: map['restrictedMessage'] as String? ?? 'Access to this application is restricted by parent settings.',
      subscriptionActive: map['subscriptionActive'] as bool? ?? true,
      parentQuote: map['parentQuote'] as String? ?? '',
      profileImageUrl: map['profileImageUrl'] as String? ?? '',
      unlockGreeting: map['unlockGreeting'] as String? ?? 'Enjoy Your Day',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'childUid': childUid,
        'parentUid': parentUid,
        'locked': locked,
        'status': status,
        'lat': lat,
        'lng': lng,
        'battery': battery,
        'fcmToken': fcmToken,
        'pendingCommand': pendingCommand,
        'pin': pin,
        'taskList': taskList,
        'hiddenApps': hiddenApps,
        'blockedApps': blockedApps,
        'taskTitle': taskTitle,
        'warningTitle': warningTitle,
        'warningList': warningList,
        'lockSchedules': lockSchedules.map((s) => s.toMap()).toList(),
        'controlMode': controlMode,
        'tempAccess': tempAccess,
        'installedApps': installedApps,
        'usageStats': usageStats,
        'appSchedules': appSchedules,
        'lockHeadline': lockHeadline,
        'restrictedHeadline': restrictedHeadline,
        'lockMessage': lockMessage,
        'restrictedMessage': restrictedMessage,
        'subscriptionActive': subscriptionActive,
        'parentQuote': parentQuote,
        'profileImageUrl': profileImageUrl,
        'unlockGreeting': unlockGreeting,
      };

  DeviceModel copyWith({
    String? id,
    String? childUid,
    String? parentUid,
    bool? locked,
    String? status,
    double? lat,
    double? lng,
    int? battery,
    String? fcmToken,
    DateTime? lastSeen,
    String? pendingCommand,
    List<LockSchedule>? lockSchedules,
    String? taskTitle,
    List<String>? taskList,
    String? warningTitle,
    List<String>? warningList,
    String? controlMode,
    Map<String, dynamic>? tempAccess,
    List<Map<String, dynamic>>? installedApps,
    Map<String, dynamic>? usageStats,
    bool? subscriptionActive,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      childUid: childUid ?? this.childUid,
      parentUid: parentUid ?? this.parentUid,
      locked: locked ?? this.locked,
      status: status ?? this.status,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      battery: battery ?? this.battery,
      fcmToken: fcmToken ?? this.fcmToken,
      lastSeen: lastSeen ?? this.lastSeen,
      pendingCommand: pendingCommand ?? this.pendingCommand,
      lockSchedules: lockSchedules ?? this.lockSchedules,
      taskTitle: taskTitle ?? this.taskTitle,
      taskList: taskList ?? this.taskList,
      warningTitle: warningTitle ?? this.warningTitle,
      warningList: warningList ?? this.warningList,
      pin: this.pin,
      hiddenApps: this.hiddenApps,
      blockedApps: this.blockedApps,
      controlMode: controlMode ?? this.controlMode,
      tempAccess: tempAccess ?? this.tempAccess,
      installedApps: installedApps ?? this.installedApps,
      usageStats: usageStats ?? this.usageStats,
      lockHeadline: this.lockHeadline,
      restrictedHeadline: this.restrictedHeadline,
      lockMessage: this.lockMessage,
      restrictedMessage: this.restrictedMessage,
      subscriptionActive: subscriptionActive ?? this.subscriptionActive,
    );
  }

  /// Check if any enabled schedule is currently active
  bool get isScheduleLocked =>
      lockSchedules.any((s) => s.isActive(DateTime.now()));

  /// True if device should be locked (manual OR schedule)
  bool get shouldBeLocked => subscriptionActive && (locked || isScheduleLocked);

  /// True if battery is critically low
  bool get isBatteryCritical => battery < 20;

  /// True if device is considered online (seen within 5 minutes)
  bool get isOnline {
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen!).inMinutes < 5;
  }

  @override
  String toString() =>
      'DeviceModel(id=$id, locked=$locked, schedules=${lockSchedules.length}, battery=$battery%, lat=$lat, lng=$lng)';
}
