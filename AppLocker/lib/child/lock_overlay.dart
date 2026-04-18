import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../shared/firebase_service.dart';

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

  // ── Chat Dialog ────────────────────────────────────────────────────────────
  void _showChatDialog() {
    FirebaseService.instance.markMessagesRead(widget.deviceId, 'parent');
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) => _ChildChatDialog(deviceId: widget.deviceId),
    );
  }

  // ── Dialer Dialog ──────────────────────────────────────────────────────────
  void _showDialerDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) => const _DialerDialog(),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Lock icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 3),
                color: bgColor,
              ),
              child: Center(
                child: Text(
                  _isRestricted ? '🚫' : '🔒',
                  style: const TextStyle(fontSize: 50),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              widget.headline.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),

            const SizedBox(height: 20),

            // Task / warning box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  if (widget.todos.isNotEmpty) ...[
                    const SizedBox(height: 14),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      );
                    }),
                  ] else ...[
                    const SizedBox(height: 10),
                    Text(
                      widget.fallbackMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 13,
                          height: 1.5),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Action buttons (lock screen only) ──────────────────────────
            if (!_isRestricted) ...[
              Row(
                children: [
                  // Chat button
                  Expanded(
                    child: _ActionButton(
                      icon: '💬',
                      label: 'MESSAGE',
                      onTap: _showChatDialog,
                      borderColor: Colors.black,
                      textColor: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Call button
                  Expanded(
                    child: _ActionButton(
                      icon: '📞',
                      label: 'CALL',
                      onTap: _showDialerDialog,
                      borderColor: Colors.black,
                      textColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ],

            // GOT IT button — restriction screen only
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
                  height: 56,
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
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            Text(
              _isRestricted
                  ? 'This app is temporarily restricted by your parent.'
                  : 'This device is temporarily locked. Complete\nyour tasks to unlock.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withOpacity(0.5),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared action button widget ────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final Color borderColor;
  final Color textColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.borderColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Child Chat Dialog ─────────────────────────────────────────────────────────
class _ChildChatDialog extends StatefulWidget {
  final String deviceId;
  const _ChildChatDialog({required this.deviceId});

  @override
  State<_ChildChatDialog> createState() => _ChildChatDialogState();
}

class _ChildChatDialogState extends State<_ChildChatDialog> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      await FirebaseService.instance
          .sendChatMessage(widget.deviceId, text, 'child');
      _scrollToBottom();
    } catch (_) {} finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFFBBC05),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded,
                      color: Colors.white, size: 30),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Chat Now',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // ── Messages ──
            Container(
              height: 340,
              color: Colors.white,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.instance.streamChatMessages(widget.deviceId),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isNotEmpty) _scrollToBottom();
                  if (docs.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('💬', style: TextStyle(fontSize: 36)),
                            SizedBox(height: 8),
                            Text(
                              'No messages yet.\nSend your parent a message!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final isChild = data['sender'] == 'child';
                      final text = data['text'] as String? ?? '';
                      final ts = data['timestamp'] as Timestamp?;
                      final timeStr = ts != null ? _formatTime(ts.toDate()) : '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          mainAxisAlignment: isChild
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (isChild) ...[
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF9E6),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(18),
                                          topRight: Radius.circular(18),
                                          bottomRight: Radius.circular(18),
                                          bottomLeft: Radius.circular(4),
                                        ),
                                        border: Border.all(
                                            color: const Color(0xFFE5D9B6),
                                            width: 1),
                                      ),
                                      child: Text(
                                        text,
                                        style: const TextStyle(
                                          color: Color(0xFF1E293B),
                                          fontSize: 14,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                    if (timeStr.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4, left: 4),
                                        child: Text(
                                          timeStr,
                                          style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 11),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEEBF8),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(18),
                                          topRight: Radius.circular(18),
                                          bottomLeft: Radius.circular(18),
                                          bottomRight: Radius.circular(4),
                                        ),
                                        border: Border.all(
                                            color: const Color(0xFFD4CEED),
                                            width: 1),
                                      ),
                                      child: Text(
                                        text,
                                        style: const TextStyle(
                                          color: Color(0xFF1E293B),
                                          fontSize: 14,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                    if (timeStr.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4, right: 4),
                                        child: Text(
                                          timeStr,
                                          style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 11),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // ── Input ──
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border:
                            Border.all(color: Colors.grey.shade300, width: 1.2),
                      ),
                      child: TextField(
                        controller: _msgCtrl,
                        keyboardType: TextInputType.multiline,
                        maxLines: 3,
                        minLines: 1,
                        style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle:
                              TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7C3AED),
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) {
      final h = dt.hour > 12
          ? dt.hour - 12
          : (dt.hour == 0 ? 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ampm';
    }
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $h:$m $ampm';
  }
}


// ── Dialer Dialog ─────────────────────────────────────────────────────────────
class _DialerDialog extends StatefulWidget {
  const _DialerDialog();

  @override
  State<_DialerDialog> createState() => _DialerDialogState();
}

class _DialerDialogState extends State<_DialerDialog> {
  String _number = '';

  void _append(String digit) {
    if (_number.length >= 15) return;
    setState(() => _number += digit);
  }

  void _backspace() {
    if (_number.isEmpty) return;
    setState(() => _number = _number.substring(0, _number.length - 1));
  }

  Future<void> _call() async {
    if (_number.isEmpty) return;
    final uri = Uri.parse('tel:$_number');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
              color: const Color(0xFFFBBC05).withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 40,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBC05).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text('📞', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Emergency Call',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      )),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 16),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Number display ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D44),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFFFBBC05).withOpacity(0.2), width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _number.isEmpty ? 'Enter number...' : _number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _number.isEmpty
                            ? const Color(0xFF64748B)
                            : Colors.white,
                        fontSize: _number.length > 10 ? 20 : 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _backspace,
                    onLongPress: () => setState(() => _number = ''),
                    child: const Icon(Icons.backspace_outlined,
                        color: Color(0xFF64748B), size: 20),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Dial pad ──
            ...[
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['*', '0', '#'],
            ].map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: row.map((digit) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: _DialKey(
                          digit: digit,
                          onTap: () => _append(digit),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 4),

            // ── Call button ──
            GestureDetector(
              onTap: _call,
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.call_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'CALL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialKey extends StatelessWidget {
  final String digit;
  final VoidCallback onTap;

  const _DialKey({required this.digit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D44),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.white.withOpacity(0.06), width: 1),
        ),
        child: Center(
          child: Text(
            digit,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
