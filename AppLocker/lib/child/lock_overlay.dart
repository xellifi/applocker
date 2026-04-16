import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_screen.dart';

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
    this.lockTitle = 'YOUR TASKS',
    this.headline = 'LOCKED',
    this.fallbackMessage =
        'This device is temporarily locked. Complete your tasks to unlock.',
  });

  @override
  State<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<LockOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _pinController = TextEditingController();
  bool _pinError = false;
  int _tapCount = 0;
  Timer? _tapResetTimer;
  Timer? _autoUnlockTimer;
  Timer? _immersiveTimer;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  static const _platform = MethodChannel('com.parentalcontrol/lock');
  static const _kAutoUnlockTimeout = Duration(minutes: 5);

  bool get _isRestricted => widget.headline.toUpperCase() != 'LOCKED';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enforceImmersiveMode();
    _startAutoUnlockTimer();
    _immersiveTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _enforceImmersiveMode();
    });
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 24)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enforceImmersiveMode();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _autoUnlockTimer?.cancel();
    _immersiveTimer?.cancel();
    _tapResetTimer?.cancel();
    _pinController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _enforceImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  }

  void _startAutoUnlockTimer() {
    _autoUnlockTimer?.cancel();
    _autoUnlockTimer = Timer(_kAutoUnlockTimeout, _unlock);
  }

  // 10 rapid taps anywhere on the lock icon area triggers emergency PIN
  void _handleEmergencyTap() {
    _tapCount++;
    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 3), () => _tapCount = 0);
    if (_tapCount >= 10) {
      _tapCount = 0;
      _showPinDialog();
    }
  }

  void _unlock() {
    _autoUnlockTimer?.cancel();
    _immersiveTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    widget.onUnlock();
  }

  void _showPinDialog() {
    _pinController.clear();
    setState(() => _pinError = false);
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFFFFE082),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.black, width: 1.5),
          ),
          title: const Row(children: [
            Text('🔓', style: TextStyle(fontSize: 24)),
            SizedBox(width: 8),
            Text('Emergency Unlock',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              autofocus: true,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8),
              decoration: const InputDecoration(
                hintText: '· · · · · ·',
                counterText: '',
                border: OutlineInputBorder(),
                fillColor: Colors.white,
                filled: true,
              ),
              onChanged: (val) {
                if (val.length >= widget.pin.length) {
                  if (val == widget.pin) {
                    Navigator.pop(ctx);
                    _unlock();
                  } else {
                    setS(() {});
                    _pinController.clear();
                    HapticFeedback.heavyImpact();
                    setS(() => _pinError = true);
                    Future.delayed(const Duration(seconds: 2),
                        () { if (mounted) setS(() => _pinError = false); });
                  }
                }
              },
            ),
            if (_pinError)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('INCORRECT PIN',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
              ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL',
                  style: TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isRestricted
        ? const Color(0xFFE53935)
        : const Color(0xFFFBBC05);

    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _isRestricted
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: bgColor,
          body: Stack(children: [
            _buildContent(bgColor),
            // Hidden 10-tap area at top-left for emergency unlock
            Positioned(
              top: 0,
              left: 0,
              child: GestureDetector(
                onTap: _handleEmergencyTap,
                child: Container(
                    width: 60,
                    height: 60,
                    color: Colors.transparent),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildContent(Color bgColor) {
    final textColor = _isRestricted ? Colors.white : Colors.black;
    final borderColor = _isRestricted
        ? Colors.white.withOpacity(0.7)
        : Colors.black;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Lock icon — NOT tappable, just decorative
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 3),
                color: bgColor,
              ),
              child: Center(
                child: Text(
                  _isRestricted ? '🚫' : '🔒',
                  style: const TextStyle(fontSize: 54),
                ),
              ),
            ),

            const SizedBox(height: 28),

            Text(
              widget.headline.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),

            const SizedBox(height: 28),

            // Task / warning box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor, width: 1.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    widget.lockTitle.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  if (widget.todos.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ...widget.todos.map((task) {
                      final clean =
                          task.replaceFirst(RegExp(r'^\s*[•\-*]\s*'), '').trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          clean.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      );
                    }),
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.fallbackMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 14,
                          height: 1.5),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Chat button — only on lock screen, not restriction screen
            if (!_isRestricted)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ChildChatScreen(deviceId: widget.deviceId),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black, width: 1.8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('💬', style: TextStyle(fontSize: 26)),
                      SizedBox(width: 12),
                      Text(
                        'SEND MESSAGE HERE',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // GOT IT button — only on restriction screen
            if (_isRestricted) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  try {
                    await _platform.invokeMethod('goHome');
                  } catch (_) {}
                  _unlock();
                },
                child: Container(
                  width: double.infinity,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Center(
                    child: Text(
                      'GOT IT',
                      style: TextStyle(
                        color: Color(0xFFE53935),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 28),

            Text(
              _isRestricted
                  ? 'This app is temporarily restricted by your parent.'
                  : 'This device is temporarily locked. Complete\nyour tasks to unlock.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withOpacity(0.55),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
