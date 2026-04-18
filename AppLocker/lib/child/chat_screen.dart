import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/firebase_service.dart';

class ChildChatScreen extends StatefulWidget {
  final String deviceId;

  const ChildChatScreen({super.key, required this.deviceId});

  @override
  State<ChildChatScreen> createState() => _ChildChatScreenState();
}

class _ChildChatScreenState extends State<ChildChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  // Local clear: messages before this timestamp are hidden only on the child side
  DateTime? _clearedAt;

  String get _clearedAtKey => 'chat_cleared_at_${widget.deviceId}';

  @override
  void initState() {
    super.initState();
    FirebaseService.instance.markMessagesRead(widget.deviceId, 'parent');
    _loadClearedAt();
  }

  Future<void> _loadClearedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_clearedAtKey);
    if (ms != null && mounted) {
      setState(() => _clearedAt = DateTime.fromMillisecondsSinceEpoch(ms));
    }
  }

  Future<void> _clearLocalHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Chat?',
            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
        content: const Text(
          'Messages will be hidden from your view only. Your parent will still be able to see the full history.',
          style: TextStyle(color: Colors.black54, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black45)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear My View',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_clearedAtKey, now.millisecondsSinceEpoch);
    if (mounted) setState(() => _clearedAt = now);
  }

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
      await FirebaseService.instance.sendChatMessage(widget.deviceId, text, 'child');
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBBC05),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFBBC05),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Text('💬', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text(
              'MESSAGE PARENT',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.black54),
            tooltip: 'Clear my view',
            onPressed: _clearLocalHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.instance.streamChatMessages(widget.deviceId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black54),
                  );
                }
                final allDocs = snapshot.data?.docs ?? [];
                // Filter out messages before the local clear timestamp
                final docs = _clearedAt == null
                    ? allDocs
                    : allDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final ts = data['timestamp'] as Timestamp?;
                        if (ts == null) return true;
                        return ts.toDate().isAfter(_clearedAt!);
                      }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No messages yet.\nSend your parent a message!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(15, 12, 15, 15),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final isChild = data['sender'] == 'child';
                    final text = data['text'] as String? ?? '';
                    final ts = data['timestamp'] as Timestamp?;
                    final timeStr = ts != null
                        ? _formatTime(ts.toDate())
                        : '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: isChild
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isChild) ...[
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                                border: Border.all(color: Colors.black, width: 1.5),
                              ),
                              child: const Center(
                                child: Text('👨‍👩‍👦',
                                    style: TextStyle(fontSize: 16)),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Column(
                              crossAxisAlignment: isChild
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isChild
                                        ? Colors.black
                                        : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: isChild
                                          ? const Radius.circular(18)
                                          : const Radius.circular(4),
                                      bottomRight: isChild
                                          ? const Radius.circular(4)
                                          : const Radius.circular(18),
                                    ),
                                    border: Border.all(
                                        color: Colors.black, width: 1.2),
                                  ),
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      color: isChild
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (timeStr.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      timeStr,
                                      style: const TextStyle(
                                          color: Colors.black45,
                                          fontSize: 10),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isChild) const SizedBox(width: 8),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(15, 8, 15, 15),
            decoration: const BoxDecoration(
              color: Color(0xFFFBBC05),
              border: Border(top: BorderSide(color: Colors.black26, width: 1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border:
                          Border.all(color: Colors.black, width: 1.5),
                    ),
                    child: TextField(
                      controller: _msgCtrl,
                      keyboardType: TextInputType.multiline,
                      maxLines: 6,
                      minLines: 3,
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Colors.black38),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5),
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    if (isToday) {
      final h = dt.hour > 12
          ? dt.hour - 12
          : (dt.hour == 0 ? 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ampm';
    }
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
