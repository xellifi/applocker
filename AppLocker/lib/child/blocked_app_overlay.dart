import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:heroicons/heroicons.dart';

class BlockedAppOverlay extends StatefulWidget {
  final String packageName;
  final String warningTitle;
  final List<String> warningList;
  final VoidCallback onDismiss;

  const BlockedAppOverlay({
    super.key,
    required this.packageName,
    required this.warningTitle,
    required this.warningList,
    required this.onDismiss,
  });

  @override
  State<BlockedAppOverlay> createState() => _BlockedAppOverlayState();
}

class _BlockedAppOverlayState extends State<BlockedAppOverlay> {
  String _appName = '';

  @override
  void initState() {
    super.initState();
    _appName = widget.packageName; // Fallback
    _fetchAppName();
  }

  Future<void> _fetchAppName() async {
    try {
      const channel = MethodChannel('com.parentalcontrol/lock');
      final name = await channel.invokeMethod<String>(
        'getAppName',
        {'packageName': widget.packageName},
      );
      if (mounted && name != null) {
        setState(() => _appName = name);
      }
    } catch (e) {
      debugPrint('//TEST: _fetchAppName error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBBC05), // Amber 600
      body: Center(
        child: Container(
          width: 340,
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE082), // Light Amber / Cream
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.black, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Custom Lock Icon
              _buildLockIcon(),

              const SizedBox(height: 24),

              Text(
                widget.warningTitle.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                _appName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),

              const SizedBox(height: 24),

              // Warning List
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  children: [
                    if (widget.warningList.isNotEmpty)
                      ...widget.warningList.map((w) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.block_flipped, color: Colors.red, size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                w,
                                style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ))
                    else
                      const Text(
                        "Access to this application is restricted by parent settings.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.5),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // RETURN HOME Button (Red)
              GestureDetector(
                onTap: () async {
                  try {
                    const MethodChannel('com.parentalcontrol/lock').invokeMethod('goHome');
                  } catch (e) {
                    debugPrint('//TEST: Native goHome error: $e');
                  }
                  widget.onDismiss();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD50000), // Pure Red
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black, width: 1.2),
                  ),
                  child: const Center(
                    child: Text(
                      'RETURN HOME',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
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

  Widget _buildLockIcon() {
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.lock_rounded,
            size: 56,
            color: Colors.black,
          ),
          Opacity(
            opacity: 0.9,
            child: HeroIcon(
              HeroIcons.noSymbol,
              color: Colors.red,
              size: 100,
              style: HeroIconStyle.outline,
            ),
          ),
        ],
      ),
    );
  }
}

