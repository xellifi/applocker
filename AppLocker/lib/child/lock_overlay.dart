// lib/child/lock_overlay.dart
// Full-screen lock overlay widget
//
// Features:
//   - Black fullscreen with "Locked by Parent" message
//   - PIN entry (default: "1234")
//   - 5-minute auto-timeout (safety: auto-unlock locally if server unreachable)
//   - 10x tap on top-left corner → open Android Settings (emergency escape)
//   - Immersive sticky mode (hide status/nav bar)
//
// SAFETY: PIN is "1234" by default. Change via parent dashboard.
// TEST: Lock device, enter "1234" → should unlock.
// TEST: Lock device, wait 5min → should auto-unlock.
// TEST: Lock device, tap top-left 10x → Android Settings should open.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
// import 'package:heroicons/heroicons.dart';

class LockOverlay extends StatefulWidget {
  final String deviceId;
  final VoidCallback onUnlock;
  final String pin;
  final List<String> todos;
  final String lockTitle;
  final String headline;
  final String fallbackMessage;

  const LockOverlay({
    super.key,
    required this.deviceId,
    required this.onUnlock,
    this.pin = '1234',
    this.todos = const [],
    this.lockTitle = "Mother's To-Do List",
    this.headline = 'LOCKED',
    this.fallbackMessage = "This device is locked by your parent.\nPlease complete your routines to unlock.",
  });

  @override
  State<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<LockOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _pinController = TextEditingController();
  final _focusNode = FocusNode();
  bool _showPinEntry = false;
  bool _pinError = false;
  int _tapCount = 0;
  Timer? _tapResetTimer;
  Timer? _autoUnlockTimer;
  Timer? _immersiveTimer;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _blinkController;

  static const _platform = MethodChannel('com.parentalcontrol/lock');
  static const _kAutoUnlockTimeout = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _enforceImmersiveMode();
    _startAutoUnlockTimer();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    // Periodic fallback: re-enforce immersive every 800ms
    _immersiveTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _enforceImmersiveMode();
    });

    // Shake animation for wrong PIN
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 24)
        .chain(
          CurveTween(curve: Curves.elasticIn),
        )
        .animate(_shakeController);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enforceImmersiveMode();
      debugPrint('//TEST: Re-enforced immersive on resume');
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _shakeController.dispose();
    _autoUnlockTimer?.cancel();
    _immersiveTimer?.cancel();
    _tapResetTimer?.cancel();
    _pinController.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _enforceImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  Future<void> _bringToForeground() async {
    try {
      await _platform.invokeMethod('bringToForeground');
      debugPrint('//TEST: Brought app back to foreground');
    } catch (e) {
      debugPrint('//TEST: bringToForeground error: $e');
    }
  }

  void _startAutoUnlockTimer() {
    _autoUnlockTimer?.cancel();
    _autoUnlockTimer = Timer(_kAutoUnlockTimeout, () {
      debugPrint('//TEST: Auto-unlock timeout reached (5 min safety)');
      _unlock();
    });
  }

  void _handleTopLeftTap() {
    _tapCount++;
    debugPrint('//TEST: Top-left tap count: $_tapCount');

    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 3), () {
      _tapCount = 0;
    });

    if (_tapCount >= 10) {
      _tapCount = 0;
      debugPrint('//TEST: Emergency escape: opening Settings');
      _openSettings();
    }
  }

  Future<void> _openSettings() async {
    try {
      await _platform.invokeMethod('openSettings');
    } catch (e) {
      debugPrint('//TEST: openSettings error: $e');
      // Fallback: show PIN entry
      setState(() => _showPinEntry = true);
    }
  }

  void _togglePinEntry() {
    setState(() {
      _showPinEntry = !_showPinEntry;
      _pinController.clear();
      _pinError = false;
    });
    if (_showPinEntry) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _focusNode.requestFocus();
      });
    }
  }

  void _validatePin() {
    final entered = _pinController.text.trim();
    debugPrint('//TEST: PIN attempt: $entered (correct: ${widget.pin})');

    if (entered == widget.pin) {
      debugPrint('//TEST: PIN correct → unlocking');
      _unlock();
    } else {
      setState(() => _pinError = true);
      _shakeController.forward(from: 0);
      _pinController.clear();
      HapticFeedback.heavyImpact();

      // Reset error after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _pinError = false);
      });
    }
  }

  void _unlock() {
    _autoUnlockTimer?.cancel();
    _immersiveTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    widget.onUnlock();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Block Android back button entirely
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBBC05), // Amber 600
          body: Stack(
            children: [
              // Main lock content
              _buildLockContent(),

              // Emergency tap zone (top-left corner, 60x60)
              Positioned(
                top: 0,
                left: 0,
                child: GestureDetector(
                  key: const Key('emergency_tap_zone'),
                  onTap: _handleTopLeftTap,
                  child: Container(
                    width: 60,
                    height: 60,
                    color: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTodoListDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFFE082), // Light Amber
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.black, width: 1.5)),
          title: Row(
            children: [
              const Icon(Icons.checklist_rounded, color: Colors.black),
              const SizedBox(width: 8),
              Text(
                widget.lockTitle,
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: widget.todos.isEmpty
                ? const Text(
                    "No tasks assigned right now! 🎉\nWait for parent to unlock your device.",
                    style: TextStyle(
                        color: Colors.black54, fontStyle: FontStyle.italic))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.todos
                        .map((t) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(Icons.check_circle_outline,
                                        color: Colors.black38, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(t,
                                          style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 14))),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('GOT IT',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLockContent() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Custom Lock Icon
                _buildLockIcon(),

                const SizedBox(height: 32),

                Column(
                  children: [
                    Text(
                      widget.headline.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Secondary Title
                const Text(
                  'Enter PIN Code to unlock',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 16),

                // PIN Input Box
                Container(
                  height: 60,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 1.0),
                  ),
                  child: Center(
                    child: TextField(
                      key: const Key('pin_input'),
                      controller: _pinController,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.number,
                      obscureText: false,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 12,
                      ),
                      decoration: const InputDecoration(
                        hintText: '* * * * * *',
                        hintStyle: TextStyle(
                          color: Colors.black26,
                          fontSize: 24,
                          letterSpacing: 4,
                        ),
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _validatePin(),
                      onChanged: (val) {
                        if (val.length >= widget.pin.length) {
                          _validatePin();
                        }
                      },
                    ),
                  ),
                ),

                if (_pinError)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'INCORRECT PIN',
                      style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),

                const SizedBox(height: 10),

                // TASK LIST CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black, width: 1.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.lockTitle.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFE65100), // Deep Orange
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (widget.todos.isNotEmpty) 
                        ...widget.todos.map((task) {
                          // Clean potential bullet from the task string
                          final cleanTask = task.replaceFirst(RegExp(r'^\s*[•\-*]\s*'), '').trim();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              cleanTask,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  widget.fallbackMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 24),

                // DISMISS / RETURN HOME Button (Only if it's an app restriction)
                if (widget.headline != 'LOCKED')
                  GestureDetector(
                    onTap: () async {
                      try {
                        const MethodChannel('com.parentalcontrol/lock').invokeMethod('goHome');
                      } catch (e) {
                        debugPrint('//TEST: Native goHome error: $e');
                      }
                      _unlock();
                    },
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F), // Pure Red
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 1.5),
                        boxShadow: [
                           BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'RETURN TO HOME',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildLockIcon() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2.0),
      ),
      child: const Center(
        child: Text(
          '🔒',
          style: TextStyle(fontSize: 64),
        ),
      ),
    );
  }

  Widget _buildPinOverlay() {
    // This is now redundant since PIN is on the main card,
    // but we can return an empty container or remove it.
    return const SizedBox.shrink();
  }
}
