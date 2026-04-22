// lib/shared/plan_gate.dart
// Centralised plan + feature gating for the parent dashboard.

import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PlanFeatures {
  final bool appRestrictions;
  final bool scheduleLock;
  final bool appFilter;
  final bool childMonitoring;
  final bool liveLocation;
  final bool chat;
  final bool masterPin;
  final int deviceLimit;
  final int blockedAppsLimit;
  final int hiddenAppsLimit;

  const PlanFeatures({
    this.appRestrictions = true,
    this.scheduleLock = true,
    this.appFilter = true,
    this.childMonitoring = true,
    this.liveLocation = true,
    this.chat = true,
    this.masterPin = true,
    this.deviceLimit = 1,
    this.blockedAppsLimit = 5,
    this.hiddenAppsLimit = 2,
  });

  factory PlanFeatures.fromMap(Map<String, dynamic> p) {
    final f = (p['features'] is Map)
        ? Map<String, dynamic>.from(p['features'] as Map)
        : <String, dynamic>{};
    bool b(String k, bool def) => (f[k] is bool) ? f[k] as bool : def;
    int i(dynamic v, int def) => v == null ? def : (int.tryParse(v.toString()) ?? def);
    return PlanFeatures(
      appRestrictions: b('appRestrictions', true),
      scheduleLock: b('scheduleLock', true),
      appFilter: b('appFilter', true),
      childMonitoring: b('childMonitoring', true),
      liveLocation: b('liveLocation', true),
      chat: b('chat', true),
      masterPin: b('masterPin', true),
      deviceLimit: i(p['deviceLimit'], 1),
      blockedAppsLimit: i(p['blockedAppsLimit'], 5),
      hiddenAppsLimit: i(p['hiddenAppsLimit'], 2),
    );
  }

  PlanFeatures copyWithMonitoringOff() => PlanFeatures(
    appRestrictions: appRestrictions, scheduleLock: scheduleLock,
    appFilter: appFilter, childMonitoring: false,
    liveLocation: liveLocation, chat: chat, masterPin: masterPin,
    deviceLimit: deviceLimit, blockedAppsLimit: blockedAppsLimit, hiddenAppsLimit: hiddenAppsLimit,
  );

  static const PlanFeatures trial = PlanFeatures(
    appRestrictions: true,
    scheduleLock: false,
    appFilter: false,
    childMonitoring: false,
    liveLocation: true,
    chat: true,
    masterPin: false,
    deviceLimit: 1,
    blockedAppsLimit: 1,
    hiddenAppsLimit: 0,
  );

  static const PlanFeatures free = PlanFeatures(
    appRestrictions: true,
    scheduleLock: false,
    appFilter: false,
    childMonitoring: false,
    liveLocation: false,
    chat: true,
    masterPin: false,
    deviceLimit: 1,
    blockedAppsLimit: 5,
    hiddenAppsLimit: 0,
  );
}

class PlanGate {
  static final Map<String, PlanFeatures> _cache = {};

  /// Fetch the current user's plan id (lowercased) and whether their subscription is expired.
  static Future<({String planId, bool expired})> currentPlan(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final plan = (data['plan'] ?? 'free').toString().toLowerCase();
      final exp = (data['expiryDate'] as Timestamp?)?.toDate();
      final expired = exp != null && exp.isBefore(DateTime.now()) && plan != 'free';
      return (planId: plan, expired: expired);
    } catch (_) {
      return (planId: 'free', expired: false);
    }
  }

  /// Convenience: gate by feature for the currently signed-in user.
  static Future<bool> requireForUser(
    BuildContext context,
    String uid,
    bool Function(PlanFeatures) check, {
    String featureLabel = 'this feature',
  }) async {
    final cur = await currentPlan(uid);
    if (cur.expired) {
      if (context.mounted) showUpgradeDialog(context, featureLabel: featureLabel);
      return false;
    }
    return require(context, cur.planId, check, featureLabel: featureLabel);
  }

  static Future<PlanFeatures> load(String planId) async {
    final id = planId.toLowerCase();
    if (id == 'trial') return PlanFeatures.trial;
    if (_cache.containsKey(id)) return _cache[id]!;
    try {
      final doc = await FirebaseFirestore.instance.collection('plans').doc(id).get();
      if (doc.exists) {
        final f = PlanFeatures.fromMap(doc.data() as Map<String, dynamic>);
        _cache[id] = f;
        return f;
      }
    } catch (_) {}
    return id == 'free' ? PlanFeatures.free : const PlanFeatures();
  }

  /// Check that a feature is enabled for the current user; if not, show the
  /// "upgrade your account" dialog and return false. Returns true if allowed.
  static Future<bool> require(
    BuildContext context,
    String planId,
    bool Function(PlanFeatures) check, {
    String featureLabel = 'this feature',
  }) async {
    final f = await load(planId);
    if (check(f)) return true;
    if (context.mounted) showUpgradeDialog(context, featureLabel: featureLabel);
    return false;
  }

  static void showUpgradeDialog(BuildContext context, {String featureLabel = 'this feature'}) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.4), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 16),
              Text('Upgrade Required',
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Text('Upgrade your account to use $featureLabel.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(fontSize: 13, color: Colors.white70, height: 1.5)),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text('Not Now',
                        style: GoogleFonts.outfit(color: Colors.white60, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      html.window.localStorage['applocker_dashboard_menu'] = 'subscriptions';
                      // The dashboard re-reads localStorage on next paint; force reload.
                      html.window.location.reload();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFBBF24),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Upgrade Now',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── Browser fingerprint for anti-trial-abuse ───────────────────────────────
  static String browserFingerprint() {
    try {
      final n = html.window.navigator;
      final s = html.window.screen;
      final parts = <String>[
        n.userAgent ?? '',
        n.language ?? '',
        n.platform ?? '',
        '${s?.width ?? 0}x${s?.height ?? 0}',
        '${(s?.colorDepth ?? 0)}',
        DateTime.now().timeZoneName,
      ];
      final raw = parts.join('|');
      final digest = sha256.convert(utf8.encode(raw)).toString();
      return digest;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Returns true if this browser already used a trial.
  static Future<bool> isTrialAlreadyUsed() async {
    try {
      final fp = browserFingerprint();
      final doc = await FirebaseFirestore.instance.collection('trial_fingerprints').doc(fp).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Records this browser as having used a trial. Also stores under the user uid.
  static Future<void> recordTrialUse(String uid, String email) async {
    try {
      final fp = browserFingerprint();
      await FirebaseFirestore.instance.collection('trial_fingerprints').doc(fp).set({
        'uid': uid,
        'email': email,
        'usedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Returns true if the device model+id was already used in a trial by another parent.
  static Future<bool> isDeviceTrialBlocked(String parentUid, String deviceModel) async {
    try {
      if (deviceModel.isEmpty || deviceModel == 'Unknown') return false;
      final key = sha256.convert(utf8.encode(deviceModel.trim().toLowerCase())).toString();
      final doc = await FirebaseFirestore.instance.collection('trial_devices').doc(key).get();
      if (!doc.exists) return false;
      final data = doc.data() as Map<String, dynamic>?;
      final usedBy = data?['parentUid'] as String?;
      // Only block if a different parent claimed this device on a trial
      return usedBy != null && usedBy != parentUid;
    } catch (_) {
      return false;
    }
  }

  static Future<void> recordDeviceTrialUse(String parentUid, String deviceModel, String deviceId) async {
    try {
      if (deviceModel.isEmpty || deviceModel == 'Unknown') return;
      final key = sha256.convert(utf8.encode(deviceModel.trim().toLowerCase())).toString();
      await FirebaseFirestore.instance.collection('trial_devices').doc(key).set({
        'parentUid': parentUid,
        'deviceId': deviceId,
        'deviceModel': deviceModel,
        'usedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
