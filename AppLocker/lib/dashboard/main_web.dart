// lib/dashboard/main_web.dart
// Parent PWA Dashboard entry point
// Build: flutter build web --target lib/dashboard/main_web.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/firebase_service.dart';
import '../firebase_options.dart';
import 'dashboard_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:convert';
import 'dart:math';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    runApp(const ParentDashboardApp());
  } catch (e) {
    runApp(_StartupErrorApp(error: e.toString()));
  }
}

// ─── Browser Detection ────────────────────────────────────────────────────────
class _BrowserInfo {
  static String? _ua;
  static String get _userAgent {
    _ua ??= html.window.navigator.userAgent.toLowerCase();
    return _ua!;
  }

  /// Messenger / Facebook in-app browser (FBAN / FBAV / FB_IAB)
  static bool get isMessengerBrowser {
    final ua = _userAgent;
    return ua.contains('fban') ||
        ua.contains('fbav') ||
        ua.contains('fb_iab') ||
        ua.contains('messenger');
  }

  /// Any Meta in-app browser (Facebook, Instagram, WhatsApp WebView)
  static bool get isMetaInAppBrowser {
    final ua = _userAgent;
    return isMessengerBrowser ||
        ua.contains('instagram') ||
        ua.contains('facebookexternalhit');
  }

  /// Generic in-app browser / WebView that blocks PWA install
  static bool get isInAppBrowser {
    final ua = _userAgent;
    return isMetaInAppBrowser ||
        ua.contains('wv)') || // Android WebView
        ua.contains('; wv') ||
        ua.contains('micromessenger') || // WeChat
        ua.contains('line/') || // LINE
        ua.contains('snapchat');
  }

  static bool get isIOS {
    final ua = _userAgent;
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  }

  static bool get isSafari {
    final ua = _userAgent;
    return ua.contains('safari') &&
        !ua.contains('chrome') &&
        !ua.contains('crios') &&
        !ua.contains('fxios');
  }

  static bool get isChrome {
    final ua = _userAgent;
    return (ua.contains('chrome') || ua.contains('crios')) &&
        !ua.contains('edg/') &&
        !ua.contains('opr/');
  }

  static bool get supportsInstallPrompt =>
      !isInAppBrowser && !isSafari && !isIOS;
}

// ─── PWA Install helper (JS interop) ──────────────────────────────────────────
//
// beforeinstallprompt fires at page-load time — before Flutter even downloads.
// index.html captures it into window._pwaPrompt via plain JS.
// We read that global here so we never miss it.
//
class _PwaInstallManager {
  static bool _installed = false;

  // Session-only dismissed flag (resets on every page load)
  static bool _sessionDismissed = false;

  static void init(VoidCallback onPromptAvailable) {
    // Already marked as installed from a previous session?
    if (html.window.localStorage['pwa_installed'] == 'true') {
      _installed = true;
      return;
    }

    // Running as installed PWA (standalone/fullscreen)? Never show banner.
    try {
      final isStandalone = js.context.callMethod('eval', [
        "window.matchMedia('(display-mode: standalone)').matches || window.matchMedia('(display-mode: fullscreen)').matches || window.navigator.standalone === true"
      ]);
      if (isStandalone == true) {
        _installed = true;
        html.window.localStorage['pwa_installed'] = 'true';
        return;
      }
    } catch (_) {}

    // In-app browsers will never have the prompt — show banner with guidance.
    if (_BrowserInfo.isInAppBrowser) {
      onPromptAvailable();
      return;
    }

    // If the event was captured by index.html JS before Flutter loaded, fire now.
    if (js.context['_pwaPrompt'] != null) {
      onPromptAvailable();
    }

    // Register callback so if it fires after Flutter loads (rare), we handle it.
    js.context['_pwaPromptCallback'] = js.allowInterop(() {
      if (!_sessionDismissed && !_installed) onPromptAvailable();
    });

    // Listen for install completion
    js.context['_pwaInstalledCallback'] = js.allowInterop(() {
      _installed = true;
    });

    // Fallback: always show the banner after 3s so users know they can install
    Future.delayed(const Duration(seconds: 3), () {
      if (!_sessionDismissed && !_installed) {
        onPromptAvailable();
      }
    });
  }

  static bool get canInstall =>
      js.context['_pwaPrompt'] != null && !_installed;

  static bool get isInstalled =>
      _installed;

  static String get installReason {
    try {
      return js.context.callMethod('getPwaInstallReason', [])?.toString() ??
          'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  static Map<String, dynamic> get installDebug {
    try {
      final raw = js.context.callMethod('getPwaInstallDebug', [])?.toString();
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
  }

  static String openInstallTarget() {
    try {
      return js.context.callMethod('openPwaInstallTarget', [])?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> prompt() async {
    try {
      final result = js.context.callMethod('triggerPwaInstall', []);
      return result?.toString() ?? 'no_prompt:unknown';
    } catch (e) {
      js.context['_pwaPrompt'] = null;
      return 'no_prompt:js_error';
    }
  }

  // Dismiss only for this session — banner returns on next visit
  static void dismiss() {
    _sessionDismissed = true;
  }
}

// ─── App root ─────────────────────────────────────────────────────────────────
class ParentDashboardApp extends StatefulWidget {
  const ParentDashboardApp({super.key});
  @override
  State<ParentDashboardApp> createState() => _ParentDashboardAppState();
}

class _ParentDashboardAppState extends State<ParentDashboardApp> {
  bool _showInstallBanner = false;

  @override
  void initState() {
    super.initState();
    _PwaInstallManager.init(() {
      if (mounted) setState(() => _showInstallBanner = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppLocker Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF060D1F),
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF6366F1),
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFFA855F7),
          surface: const Color(0xFF060D1F),
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.outfitTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF060D1F),
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF6366F1),
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFFA855F7),
          surface: const Color(0xFF060D1F),
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.outfitTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
      ),
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) => Stack(
          children: [
            const _AppShell(),
            if (_showInstallBanner)
              _PwaInstallBanner(
                onInstall: () {
                  setState(() => _showInstallBanner = false);
                },
                onDismiss: () {
                  _PwaInstallManager.dismiss();
                  setState(() => _showInstallBanner = false);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ─── App shell (onboarding → login / dashboard) ───────────────────────────────
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  bool _onboardingDone = false;

  @override
  void initState() {
    super.initState();
    // Onboarding is now the permanent home page for every visit.
    // Logged-in users skip it and go straight to the dashboard.
    _onboardingDone = FirebaseAuth.instance.currentUser != null;
    html.window.localStorage.remove('applocker_onboarding_done');
  }

  void _finishOnboarding() {
    setState(() => _onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF060D1F),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
          );
        }
        if (snapshot.hasData) {
          html.window.localStorage['applocker_logged_in'] = 'true';
          return const DashboardScreen();
        }
        html.window.localStorage.remove('applocker_logged_in');
        if (!_onboardingDone) {
          return OnboardingScreen(onDone: _finishOnboarding);
        }
        return const LoginScreen();
      },
    );
  }
}

// ─── PWA Install Banner ────────────────────────────────────────────────────────
class _PwaInstallBanner extends StatefulWidget {
  final VoidCallback onInstall;
  final VoidCallback onDismiss;
  const _PwaInstallBanner({required this.onInstall, required this.onDismiss});

  @override
  State<_PwaInstallBanner> createState() => _PwaInstallBannerState();
}

class _PwaInstallBannerState extends State<_PwaInstallBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slideAnim = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleInstall() {
    _PwaInstallManager.prompt().then((result) {
      if (!mounted) return;
      if (result == 'prompted') return;
      final reason = result.startsWith('no_prompt:')
          ? result.substring('no_prompt:'.length)
          : _PwaInstallManager.installReason;
      if (reason == 'embedded_preview') {
        _showDirectInstallDialog();
      } else {
        _showManualInstallGuide(reason: reason);
      }
    });
  }

  void _showDirectInstallDialog() {
    final debug = _PwaInstallManager.installDebug;
    final targetUrl = (debug['directInstallUrl'] ?? '').toString();
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 32)],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Open AppLocker to install',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, decoration: TextDecoration.none))),
                GestureDetector(
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                ),
              ]),
              const SizedBox(height: 10),
              Text('The app-style install prompt cannot appear inside this preview window. Open AppLocker directly, then tap Install App again to trigger the native browser install popup.',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70, height: 1.5, decoration: TextDecoration.none)),
              if (targetUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(targetUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 11, color: Colors.white38, height: 1.4, decoration: TextDecoration.none)),
              ],
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () {
                  _PwaInstallManager.openInstallTarget();
                  Navigator.of(context, rootNavigator: true).pop();
                },
                child: Container(
                  width: double.infinity, height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text('Open Install Page',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, decoration: TextDecoration.none))),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Navigator.of(context, rootNavigator: true).pop();
                  _showManualInstallGuide(reason: 'embedded_preview');
                },
                child: Center(child: Text('Show manual steps instead',
                  style: GoogleFonts.outfit(color: Colors.white54, fontWeight: FontWeight.w600, fontSize: 12, decoration: TextDecoration.none))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualInstallGuide({String reason = 'waiting_for_browser'}) {
    final message = switch (reason) {
      'insecure_context' => 'The browser requires a secure HTTPS page before it can show the app install popup.',
      'service_worker_unavailable' => 'This browser does not support the service worker needed for app installation.',
      'dismissed' => 'Chrome paused the native popup after it was dismissed. You can still install from the browser menu.',
      'embedded_preview' => 'The preview window cannot show the native install popup. Open the app directly or use these steps.',
      _ => 'Chrome is not ready to show the app install popup yet. Use this quick method instead:',
    };
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 32)],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.install_mobile_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Install AppLocker',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, decoration: TextDecoration.none))),
                GestureDetector(
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                ),
              ]),
              const SizedBox(height: 8),
              Text(message,
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.white54, height: 1.5, decoration: TextDecoration.none)),
              const SizedBox(height: 20),
              _guideStep('1', Icons.more_vert_rounded, 'Tap the menu (⋮)',
                  'Top-right corner of Chrome browser'),
              const SizedBox(height: 14),
              _guideStep('2', Icons.add_to_home_screen_rounded, 'Tap "Add to Home screen"',
                  'Or "Install app" — both do the same thing'),
              const SizedBox(height: 14),
              _guideStep('3', Icons.check_circle_outline_rounded, 'Tap "Add" to confirm',
                  'AppLocker appears on your home screen instantly'),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                child: Container(
                  width: double.infinity, height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text('Got it!',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, decoration: TextDecoration.none))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideStep(String num, IconData icon, String label, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Text(num,
            style: GoogleFonts.outfit(color: const Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 13, decoration: TextDecoration.none))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, decoration: TextDecoration.none)),
          Text(sub, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11, height: 1.4, decoration: TextDecoration.none)),
        ])),
      ],
    );
  }

  // DEAD CODE kept for reference — no longer called
  void _showInstallInstructions(BuildContext context) {
    final isInApp = _BrowserInfo.isInAppBrowser;
    final isMessenger = _BrowserInfo.isMessengerBrowser;
    final isIOS = _BrowserInfo.isIOS;
    final isSafari = _BrowserInfo.isSafari;

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF6366F1).withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withOpacity(0.2),
                blurRadius: 40,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.install_mobile_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Install AppLocker',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(dialogCtx, rootNavigator: true).pop(),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white54, size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── In-App Browser Notice (Messenger / FB / Instagram etc.) ──
              if (isInApp) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFF59E0B), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isMessenger
                              ? 'Messenger Browser Detected'
                              : 'In-App Browser Detected',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFF59E0B),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        isMessenger
                            ? 'Messenger\'s browser cannot install apps. Please open this page in Chrome or Safari to install AppLocker.'
                            : 'This in-app browser cannot install PWAs. Open this page in Chrome or Safari to install AppLocker.',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.white70,
                          height: 1.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _InstructionStep(
                  icon: Icons.open_in_browser_rounded,
                  label: 'Step 1 — Copy the link',
                  detail: 'Tap the 3-dot menu (⋮) or the share icon and choose "Open in browser" or "Open in Chrome".',
                ),
                const SizedBox(height: 12),
                _InstructionStep(
                  icon: Icons.download_rounded,
                  label: 'Step 2 — Install from Chrome',
                  detail: 'Once in Chrome, tap the 3-dot menu → "Add to Home screen" or "Install app".',
                ),
              ] else ...[
                // ── Normal install instructions ───────────────────────
                if (isIOS && isSafari) ...[
                  _InstructionStep(
                    icon: Icons.ios_share_rounded,
                    label: 'Safari (iPhone / iPad)',
                    detail: 'Tap the Share button (□↑) at the bottom → scroll down → tap "Add to Home Screen".',
                  ),
                  const SizedBox(height: 12),
                  _InstructionStep(
                    icon: Icons.info_outline_rounded,
                    label: 'Tip',
                    detail: 'If you\'re on iPhone, make sure to use Safari — other browsers on iOS cannot install apps.',
                  ),
                ] else if (isIOS) ...[
                  _InstructionStep(
                    icon: Icons.open_in_browser_rounded,
                    label: 'Open in Safari',
                    detail: 'iOS only allows app installation from Safari. Copy the link and open it in Safari.',
                  ),
                  const SizedBox(height: 12),
                  _InstructionStep(
                    icon: Icons.ios_share_rounded,
                    label: 'Then tap Share → "Add to Home Screen"',
                    detail: 'Tap the Share button (□↑) at the bottom of Safari → "Add to Home Screen".',
                  ),
                ] else ...[
                  _InstructionStep(
                    icon: Icons.desktop_windows_rounded,
                    label: 'Chrome / Edge (Desktop)',
                    detail: 'Click the install icon (⊕) in the address bar, or open the menu → "Install AppLocker".',
                  ),
                  const SizedBox(height: 12),
                  _InstructionStep(
                    icon: Icons.phone_android_rounded,
                    label: 'Chrome (Android)',
                    detail: 'Tap the 3-dot menu (⋮) → "Add to Home screen" or "Install app".',
                  ),
                  const SizedBox(height: 12),
                  _InstructionStep(
                    icon: Icons.phone_iphone_rounded,
                    label: 'Safari (iPhone / iPad)',
                    detail: 'Tap the Share button (□↑) → scroll down → "Add to Home Screen".',
                  ),
                ],
              ],

              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.of(dialogCtx, rootNavigator: true).pop(),
                child: Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Center(
                    child: Text(
                      'Got it',
                      style: GoogleFonts.outfit(
                        color: Colors.white54,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isInApp = _BrowserInfo.isInAppBrowser;
    final isMessenger = _BrowserInfo.isMessengerBrowser;
    final isIOS = _BrowserInfo.isIOS;
    final isSafari = _BrowserInfo.isSafari && isIOS;
    final canInstall = _PwaInstallManager.canInstall;

    // Show install button for any browser that can support it (and not already installed)
    final bool showInstallBtn = !isInApp && !isIOS && !_PwaInstallManager.isInstalled;
    final bool showSafariHint = isIOS && isSafari && !isInApp;
    final bool showInAppHint  = isInApp;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Positioned.fill(
        child: Opacity(
          opacity: _fadeAnim.value,
          child: Transform.scale(
            scale: _slideAnim.value,
            child: child,
          ),
        ),
      ),
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF6366F1).withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.2),
                    blurRadius: 40,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 32,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Main row ──────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.shield_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              showInAppHint
                                  ? (isMessenger ? 'Open in Chrome to install' : 'Open in Chrome to install')
                                  : showSafariHint
                                      ? 'Add to Home Screen'
                                      : 'Install AppLocker',
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            Text(
                              showInAppHint
                                  ? (isMessenger
                                      ? 'Tap ⋮ → "Open in Chrome", then install from there.'
                                      : 'Tap the share/menu icon → "Open in Chrome".')
                                  : showSafariHint
                                      ? 'Tap Share (□↑) → "Add to Home Screen".'
                                      : 'Add to your home screen for quick access.',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: Colors.white54,
                                height: 1.4,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onDismiss,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white54, size: 16),
                        ),
                      ),
                    ],
                  ),

                  // ── Install button ─────────────────────────────────────
                  if (showInstallBtn) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _handleInstall,
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.download_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Install App',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _InstructionStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  const _InstructionStep({required this.icon, required this.label, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF818CF8)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: Colors.white54,
                  height: 1.4,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Onboarding Screen ────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  late final AnimationController _bgCtrl;
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;

  static const _pages = [
    _OnboardingPage(
      gradient: [Color(0xFF060D1F), Color(0xFF0F1A35), Color(0xFF1a1050)],
      accentColor: Color(0xFF6366F1),
      icon: Icons.shield_rounded,
      badge: 'PARENTAL CONTROL',
      title: 'Control & Manage\nYour Loved Ones',
      subtitle:
          'Stay in control with AppLocker — the smartest way to monitor and protect your family\'s digital life in real time.',
      features: [],
    ),
    _OnboardingPage(
      gradient: [Color(0xFF060D1F), Color(0xFF0D1A2A), Color(0xFF071428)],
      accentColor: Color(0xFF10B981),
      icon: Icons.lock_clock_rounded,
      badge: 'SMART SCHEDULING',
      title: 'Schedule Locks &\nRestrict Any App',
      subtitle:
          'Set time-based device locks and block specific apps — automatically enforced without any action needed from you.',
      features: [
        _FeatureItem(Icons.block_rounded, 'Block any app instantly'),
        _FeatureItem(Icons.schedule_rounded, 'Auto-lock by time of day'),
        _FeatureItem(Icons.phone_locked_rounded, 'Full device lockdown'),
      ],
    ),
    _OnboardingPage(
      gradient: [Color(0xFF060D1F), Color(0xFF0F1520), Color(0xFF0a1520)],
      accentColor: Color(0xFF38BDF8),
      icon: Icons.location_on_rounded,
      badge: 'LIVE MONITORING',
      title: 'Track Location &\nAll Activities',
      subtitle:
          'See exactly where they are and what they\'re doing — GPS tracking, app usage, messages, and web activity all in one place.',
      features: [
        _FeatureItem(Icons.gps_fixed_rounded, 'Real-time GPS tracking'),
        _FeatureItem(Icons.apps_rounded, 'App usage monitoring'),
        _FeatureItem(Icons.history_rounded, 'Full activity history'),
      ],
    ),
    _OnboardingPage(
      gradient: [Color(0xFF060D1F), Color(0xFF150D2E), Color(0xFF0D0920)],
      accentColor: Color(0xFFEC4899),
      icon: Icons.family_restroom_rounded,
      badge: 'GET STARTED',
      title: 'Set Up in\nUnder a Minute',
      subtitle:
          'Pair your child\'s device by scanning a QR code. That\'s it — monitoring starts immediately, no technical skills needed.',
      features: [
        _FeatureItem(Icons.qr_code_scanner_rounded, 'Scan & pair instantly'),
        _FeatureItem(Icons.notifications_active_rounded, 'Live push alerts'),
        _FeatureItem(Icons.dashboard_rounded, 'Beautiful dashboard'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _floatCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -8, end: 8)
        .animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));
    _bgCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _bgCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic);
    } else {
      widget.onDone();
    }
  }

  void _skip() => widget.onDone();

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    final isLast = _currentPage == _pages.length - 1;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Animated gradient background
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: page.gradient,
              ),
            ),
          ),

          // Decorative orbs
          Positioned(
            top: -80, right: -80,
            child: AnimatedBuilder(
              animation: _floatAnim,
              builder: (_, __) => Transform.translate(
                offset: Offset(_floatAnim.value * 0.5, _floatAnim.value),
                child: Container(
                  width: 280, height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        page.accentColor.withOpacity(0.18),
                        page.accentColor.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 100, left: -60,
            child: AnimatedBuilder(
              animation: _floatAnim,
              builder: (_, __) => Transform.translate(
                offset: Offset(-_floatAnim.value * 0.3, -_floatAnim.value * 0.7),
                child: Container(
                  width: 200, height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        page.accentColor.withOpacity(0.12),
                        page.accentColor.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // PageView
          PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _pages.length,
            itemBuilder: (context, i) => _OnboardingPageView(
              page: _pages[i],
              floatAnim: _floatAnim,
              isMobile: isMobile,
              isActive: i == _currentPage,
            ),
          ),

          // Top bar: skip
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.shield_rounded,
                            color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Text('AppLocker',
                          style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ]),
                    if (_currentPage < _pages.length - 1)
                      GestureDetector(
                        onTap: _skip,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.12)),
                          ),
                          child: Text('Skip',
                              style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white60)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom navigation
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dot indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _currentPage ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _currentPage
                                ? page.accentColor
                                : Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Next / Get Started button
                    GestureDetector(
                      onTap: _next,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isLast
                                ? [page.accentColor, page.accentColor.withOpacity(0.7)]
                                : [
                                    const Color(0xFF6366F1),
                                    const Color(0xFF8B5CF6)
                                  ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: (isLast ? page.accentColor : const Color(0xFF6366F1))
                                  .withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isLast ? 'Get Started' : 'Next',
                              style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single onboarding page view ─────────────────────────────────────────────
class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;
  final Animation<double> floatAnim;
  final bool isMobile;
  final bool isActive;

  const _OnboardingPageView({
    required this.page,
    required this.floatAnim,
    required this.isMobile,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 160),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hero icon with orbiting rings
          AnimatedBuilder(
            animation: floatAnim,
            builder: (_, __) => Transform.translate(
              offset: Offset(0, floatAnim.value * 0.6),
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer ring
                    _RingDecor(
                        radius: 85,
                        color: page.accentColor.withOpacity(0.12),
                        borderColor: page.accentColor.withOpacity(0.2)),
                    // Middle ring
                    _RingDecor(
                        radius: 68,
                        color: page.accentColor.withOpacity(0.08),
                        borderColor: page.accentColor.withOpacity(0.15)),
                    // Icon container
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            page.accentColor,
                            page.accentColor.withOpacity(0.6),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: page.accentColor.withOpacity(0.5),
                            blurRadius: 28,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child:
                          Icon(page.icon, color: Colors.white, size: 46),
                    ),
                    // Small floating dots
                    ..._buildOrbitDots(page.accentColor),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 36),

          // Badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: page.accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: page.accentColor.withOpacity(0.3), width: 1),
            ),
            child: Text(
              page.badge,
              style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: page.accentColor,
                  letterSpacing: 2.0),
            ),
          ).animate(target: isActive ? 1 : 0).fadeIn(delay: 100.ms),

          const SizedBox(height: 16),

          // Title
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 28 : 34,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.15,
              letterSpacing: -0.5,
            ),
          ).animate(target: isActive ? 1 : 0)
              .fadeIn(delay: 200.ms)
              .moveY(begin: 20, end: 0, delay: 200.ms),

          const SizedBox(height: 14),

          // Subtitle
          Text(
            page.subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 14 : 15,
              color: Colors.white60,
              height: 1.6,
            ),
          ).animate(target: isActive ? 1 : 0)
              .fadeIn(delay: 300.ms)
              .moveY(begin: 15, end: 0, delay: 300.ms),

          if (page.features.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...page.features.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FeatureRow(item: e.value, color: page.accentColor)
                    .animate(target: isActive ? 1 : 0)
                    .fadeIn(delay: Duration(milliseconds: 400 + e.key * 100))
                    .moveX(begin: -20, end: 0,
                        delay: Duration(milliseconds: 400 + e.key * 100)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildOrbitDots(Color color) {
    const positions = [
      Offset(70, -20),
      Offset(-65, 10),
      Offset(20, 72),
      Offset(-25, -68),
    ];
    final sizes = [8.0, 6.0, 10.0, 7.0];
    return List.generate(positions.length, (i) {
      return Positioned(
        left: 90 + positions[i].dx,
        top: 90 + positions[i].dy,
        child: Container(
          width: sizes[i],
          height: sizes[i],
          decoration: BoxDecoration(
            color: color.withOpacity(0.6),
            shape: BoxShape.circle,
          ),
        ),
      );
    });
  }
}

class _RingDecor extends StatelessWidget {
  final double radius;
  final Color color;
  final Color borderColor;
  const _RingDecor(
      {required this.radius,
      required this.color,
      required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: borderColor, width: 1.5),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final _FeatureItem item;
  final Color color;
  const _FeatureRow({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Icon(item.icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Text(
          item.label,
          style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.85)),
        ),
      ],
    );
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────
class _OnboardingPage {
  final List<Color> gradient;
  final Color accentColor;
  final IconData icon;
  final String badge;
  final String title;
  final String subtitle;
  final List<_FeatureItem> features;

  const _OnboardingPage({
    required this.gradient,
    required this.accentColor,
    required this.icon,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.features,
  });
}

class _FeatureItem {
  final IconData icon;
  final String label;
  const _FeatureItem(this.icon, this.label);
}

// ─── Login Screen ─────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await FirebaseService.instance.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().contains('] ')
            ? e.toString().split('] ').last
            : e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _socialLogin(String type) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (type == 'google') {
        await FirebaseService.instance.signInWithGoogle();
      } else {
        await FirebaseService.instance.signInWithFacebook();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Social login failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF060D1F),
      body: Stack(children: [
        // Background orbs
        Positioned(
          top: -100, left: -100,
          child: Container(
            width: 400, height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF6366F1).withOpacity(0.12),
                const Color(0xFF6366F1).withOpacity(0),
              ]),
            ),
          ).animate().fadeIn(duration: 1.seconds).scale(),
        ),
        Positioned(
          bottom: -50, right: -50,
          child: Container(
            width: 500, height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF8B5CF6).withOpacity(0.1),
                const Color(0xFF8B5CF6).withOpacity(0),
              ]),
            ),
          ).animate().fadeIn(duration: 1.2.seconds, delay: 200.ms),
        ),

        Center(
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 20 : 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1A35),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.08),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: _buildLogo()),
                        const SizedBox(height: 28),

                        // Email
                        _buildLabel('Email Address'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _emailController,
                          hint: 'name@company.com',
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),

                        // Password
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildLabel('Password'),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 28),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                              child: Text('Forgot password?',
                                  style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF6366F1))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _passwordController,
                          hint: 'Enter your password',
                          icon: Icons.lock_outline_rounded,
                          obscure: _obscurePassword,
                          suffix: GestureDetector(
                            onTap: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            child: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 18,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFFEF4444).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFFEF4444)
                                      .withOpacity(0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: Color(0xFFEF4444), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_errorMessage!,
                                    style: GoogleFonts.outfit(
                                        color: const Color(0xFFEF4444),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 16),
                        ],

                        _buildSignInButton().animate().fadeIn().scale(),
                        const SizedBox(height: 24),

                        Row(children: [
                          const Expanded(
                              child: Divider(color: Color(0xFF1E293B))),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('Or login with',
                                style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: const Color(0xFF475569))),
                          ),
                          const Expanded(
                              child: Divider(color: Color(0xFF1E293B))),
                        ]),
                        const SizedBox(height: 20),
                        _buildSocialButtons(),
                        const SizedBox(height: 24),

                        Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              Text("Don't have an account? ",
                                  style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      color: const Color(0xFF64748B))),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {},
                                  child: Text("Create free account",
                                      style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF6366F1))),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 200.ms).moveY(begin: 30, end: 0),

                  const SizedBox(height: 28),
                  Text(
                    '© 2026 AppLocker Security. Secure Management.',
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w500),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
        style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF94A3B8)));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: GoogleFonts.outfit(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(
            color: const Color(0xFF475569), fontSize: 14),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF475569)),
        suffixIcon: suffix != null
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: suffix)
            : null,
        filled: true,
        fillColor: const Color(0xFF060D1F),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E293B))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E293B))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF6366F1).withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 30),
      ),
      const SizedBox(height: 14),
      RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5),
          children: const [
            TextSpan(
                text: 'App',
                style: TextStyle(color: Colors.white)),
            TextSpan(
                text: 'Locker',
                style: TextStyle(color: Color(0xFF6366F1))),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Text('PARENTAL CONTROL',
          style: GoogleFonts.outfit(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF475569),
              letterSpacing: 4)),
    ]);
  }

  Widget _buildSignInButton() {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _login,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.lock_open_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text('Sign In to Dashboard',
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                  ]),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButtons() {
    return Row(children: [
      Expanded(
          child: _SocialButton(
              label: 'Google',
              icon: Icons.g_mobiledata_rounded,
              color: const Color(0xFFEA4335),
              isOutline: true,
              onTap: () => _socialLogin('google'))),
      const SizedBox(width: 12),
      Expanded(
          child: _SocialButton(
              label: 'Facebook',
              icon: Icons.facebook_rounded,
              color: const Color(0xFF1877F2),
              isOutline: false,
              onTap: () => _socialLogin('facebook'))),
    ]);
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isOutline;
  final VoidCallback onTap;

  const _SocialButton(
      {required this.label,
      required this.icon,
      required this.color,
      required this.isOutline,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isOutline ? const Color(0xFF0F1A35) : color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isOutline
                ? const Color(0xFF1E293B)
                : color.withOpacity(0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: isOutline ? color : Colors.white,
                size: label == 'Google' ? 28 : 20),
            if (label != 'Google') const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.outfit(
                    color: isOutline
                        ? const Color(0xFF94A3B8)
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  final String error;
  const _StartupErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Startup failed:\n$error',
                textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
