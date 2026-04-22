// lib/dashboard/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart' hide Path;
import 'package:flutter/scheduler.dart';
import 'dart:ui' as ui;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:heroicons/heroicons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../shared/firebase_service.dart';
import '../shared/plan_gate.dart';
enum _DashboardMenu { dashboard, devices, apps, schedules, location, monitoring, reports, subscriptions, paymentMethods, pendingTransactions, settings, users, profile }

// GLOBAL HELPER FOR PAIRING DIALOG
void showAppLockerPairingDialog(BuildContext context, Color cardColor, Color textColor) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // Check device limit based on plan
  final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  final userData = userDoc.data() as Map<String, dynamic>? ?? {};
  final String plan = userData['plan'] ?? 'free';
  final DateTime? expiry = (userData['expiryDate'] as Timestamp?)?.toDate();
  final bool isExpired = expiry != null && expiry.isBefore(DateTime.now());

  if (isExpired && plan != 'free') {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your subscription has expired. Please renew to add devices.'), backgroundColor: Colors.redAccent),
      );
    }
    return;
  }

  int limit = 1;
  if (userData['role'] == 'super_admin') {
    limit = 999;
  } else {
    final rawPlan = (userData['plan'] ?? 'free').toString();
    final planId = rawPlan.toLowerCase();
    
    // Attempt lowercase document ID fetch
    var planDoc = await FirebaseFirestore.instance.collection('plans').doc(planId).get();
    
    // If not found by ID, try searching by name field as fallback
    if (!planDoc.exists) {
       final search = await FirebaseFirestore.instance.collection('plans').where('name', isEqualTo: rawPlan).limit(1).get();
       if (search.docs.isNotEmpty) planDoc = search.docs.first;
    }

    if (planDoc.exists) {
      final pData = planDoc.data() as Map<String, dynamic>?;
      final rawLimit = pData?['deviceLimit'];
      if (rawLimit != null) {
        limit = int.tryParse(rawLimit.toString()) ?? 1;
      }
    }
  }

  final devicesSnapshot = await FirebaseFirestore.instance.collection('devices').where('parentUid', isEqualTo: user.uid).get();
  if (devicesSnapshot.docs.length >= limit) {
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Device Limit Reached', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor)),
          content: Text('Your $plan plan is limited to $limit device(s). Please upgrade to add more.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Got It', style: GoogleFonts.outfit(color: const Color(0xFF6366F1)))),
          ],
        ),
      );
    }
    return;
  }

  final String pin = (100000 + Random().nextInt(900000)).toString();
  FirebaseService.instance.createPairingSession(user.uid, pin);
  
  final qrData = jsonEncode({'parentId': user?.uid ?? 'unknown'});
  
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      final size = MediaQuery.of(context).size;
      final isCompact = size.width < 520 || size.height < 760;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 24,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 430,
            maxHeight: size.height * 0.9,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.18)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 34, offset: const Offset(0, 18))],
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, isCompact ? 20 : 26, 24, isCompact ? 20 : 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pair New Device', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: textColor, height: 1.05)),
                            const SizedBox(height: 3),
                            Text('Scan or enter the PIN on the child app', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8))),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: const Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                  SizedBox(height: isCompact ? 18 : 24),
                  Container(
                    padding: EdgeInsets.all(isCompact ? 14 : 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 12))],
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: isCompact ? 172 : 210,
                      foregroundColor: const Color(0xFF1E293B),
                    ),
                  ),
                  SizedBox(height: isCompact ? 20 : 26),
                  Text('6-DIGIT PAIRING PIN', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.6)),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: isCompact ? 12 : 15),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [const Color(0xFF6366F1).withOpacity(0.16), const Color(0xFF8B5CF6).withOpacity(0.12)]),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.25)),
                    ),
                    child: Text(
                      pin,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(fontSize: isCompact ? 30 : 36, fontWeight: FontWeight.w900, color: const Color(0xFF6366F1), letterSpacing: 7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Keep this window open while pairing. The code is temporary and only works for your account.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  _DashboardMenu _selectedMenu = _DashboardMenu.dashboard;
  bool _isSidebarOpen = true;
  bool _isDark = true;
  bool _isExpiredFlag = false;
  String _userPlan = 'free';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _isDark = html.window.localStorage['applocker_dashboard_theme'] != 'light';
    final savedMenu = html.window.localStorage['applocker_dashboard_menu'];
    if (savedMenu != null) {
      for (final menu in _DashboardMenu.values) {
        if (menu.name == savedMenu) {
          _selectedMenu = menu;
          break;
        }
      }
    }
  }

  void _setSelectedMenu(_DashboardMenu menu) {
    if (_isExpiredFlag && menu != _DashboardMenu.subscriptions) return;
    html.window.localStorage['applocker_dashboard_menu'] = menu.name;
    setState(() => _selectedMenu = menu);
  }

  void _toggleTheme() {
    final next = !_isDark;
    html.window.localStorage['applocker_dashboard_theme'] = next ? 'dark' : 'light';
    setState(() => _isDark = next);
  }

  void _showMobileMoreSheet(BuildContext context, Color cardColor, Color textColor, String userRole) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MobileMoreSheet(
        isDark: _isDark,
        selectedMenu: _selectedMenu,
        onMenuSelected: (menu) {
          _setSelectedMenu(menu);
          Navigator.pop(context);
        },
        userRole: userRole,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
      builder: (context, userSnapshot) {
        String userRole = 'parent';
        if (userSnapshot.hasData && userSnapshot.data?.data() != null) {
          final data = userSnapshot.data!.data() as Map<String, dynamic>;
          userRole = data['role'] ?? 'parent';
          final plan = (data['plan'] ?? 'free').toString().toLowerCase();
          final expiryDate = (data['expiryDate'] as Timestamp?)?.toDate();
          final expired = expiryDate != null && expiryDate.isBefore(DateTime.now()) && plan != 'free' && userRole != 'super_admin';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_isExpiredFlag != expired || _userPlan != plan) {
              setState(() { _isExpiredFlag = expired; _userPlan = plan; });
              if (expired && _selectedMenu != _DashboardMenu.subscriptions) {
                setState(() => _selectedMenu = _DashboardMenu.subscriptions);
              }
            }
          });
        }

        final bool isMobile = MediaQuery.of(context).size.width <= 1024;
        final bgColor = _isDark
            ? (isMobile ? const Color(0xFF060D1F) : const Color(0xFF0D0D10))
            : const Color(0xFFF8FAFC);
        final cardColor = _isDark ? const Color(0xFF18181B) : Colors.white;
        final textColor = _isDark ? Colors.white : const Color(0xFF1E293B);
        final borderColor = const Color(0xFF64748B);

        if (isMobile) {
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: bgColor,
            body: SafeArea(
              child: Column(children: [
                _MobileTopBar(
                  title: _selectedMenu == _DashboardMenu.dashboard
                      ? 'AppLocker'
                      : _mobileMenuLabel(_selectedMenu),
                  isDark: _isDark,
                  userRole: userRole,
                  onThemeToggle: _toggleTheme,
                  onPrev: _selectedMenu.index > 0
                      ? () => _setSelectedMenu(
                          _DashboardMenu.values[_selectedMenu.index - 1])
                      : null,
                  onNext: _selectedMenu.index < _DashboardMenu.values.length - 1
                      ? () => _setSelectedMenu(
                          _DashboardMenu.values[_selectedMenu.index + 1])
                      : null,
                ),
                Expanded(
                  child: _buildContent(textColor, cardColor, borderColor, true, userRole),
                ),
              ]),
            ),
            bottomNavigationBar: _MobileBottomNav(
              selected: _selectedMenu,
              isDark: _isDark,
              onSelected: _setSelectedMenu,
              onMorePressed: () =>
                  _showMobileMoreSheet(context, cardColor, textColor, userRole),
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: bgColor,
          body: Row(
            children: [
              _Sidebar(
                selectedMenu: _selectedMenu,
                  onMenuSelected: _setSelectedMenu, 
                isCollapsed: !_isSidebarOpen,
                isDark: _isDark,
                userRole: userRole,
              ),
              Expanded(
                child: Column(children: [
                  _Header(
                    title: _selectedMenu.name.toUpperCase(),
                    onMenuPressed: () =>
                        setState(() => _isSidebarOpen = !_isSidebarOpen),
                    isDark: _isDark,
                    onThemeToggle: _toggleTheme,
                    isMobile: false,
                    userRole: userRole,
                    onAdminBadgeTap: userRole == 'super_admin'
                        ? () => _setSelectedMenu(_DashboardMenu.users)
                        : null,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: _buildContent(
                          textColor, cardColor, borderColor, false, userRole),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  String _mobileMenuLabel(_DashboardMenu m) {
    switch (m) {
      case _DashboardMenu.dashboard: return 'Dashboard';
      case _DashboardMenu.devices: return 'My Devices';
      case _DashboardMenu.apps: return 'App Controls';
      case _DashboardMenu.schedules: return 'Schedules';
      case _DashboardMenu.location: return 'Family Location';
      case _DashboardMenu.monitoring: return 'Activity Overview';
      case _DashboardMenu.reports: return 'Reports';
      case _DashboardMenu.subscriptions: return 'Subscription';
      case _DashboardMenu.paymentMethods: return 'Payment Methods';
      case _DashboardMenu.pendingTransactions: return 'Pending Payments';
      case _DashboardMenu.settings: return 'Settings';
      case _DashboardMenu.users: return 'Users Admin';
      case _DashboardMenu.profile: return 'My Profile';
    }
  }

  Widget _buildContent(Color textColor, Color cardColor, Color borderColor, bool isMobile, String userRole) {
    if (_isExpiredFlag) {
      return isMobile
          ? _MobileSubscriptionView(isDark: _isDark, userRole: userRole)
          : SingleChildScrollView(child: _SubscriptionView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, userRole: userRole));
    }
    if (isMobile) {
      switch (_selectedMenu) {
        case _DashboardMenu.dashboard: return _MobileDashboardHome(isDark: _isDark, userRole: userRole, onNavigate: _setSelectedMenu);
        case _DashboardMenu.devices: return _MobileDevicesView(isDark: _isDark, userRole: userRole, onNavigate: _setSelectedMenu);
        case _DashboardMenu.apps: return _MobileAppControlsView(isDark: _isDark, onNavigate: _setSelectedMenu);
        case _DashboardMenu.schedules: return _MobileSchedulesView(isDark: _isDark);
        case _DashboardMenu.location: return _MobileLocationView(isDark: _isDark, onNavigate: _setSelectedMenu);
        case _DashboardMenu.monitoring: return _MobileMonitoringView(isDark: _isDark);
        case _DashboardMenu.reports: return _MobileReportsView(isDark: _isDark);
        case _DashboardMenu.subscriptions: return _MobileSubscriptionView(isDark: _isDark, userRole: userRole);
        case _DashboardMenu.paymentMethods: return _PaymentMethodsView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor);
        case _DashboardMenu.pendingTransactions: return _PendingTransactionsView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor);
        case _DashboardMenu.settings: return _MobileSettingsView(isDark: _isDark);
        case _DashboardMenu.users: return SingleChildScrollView(child: _UsersList(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, isMobile: true));
        case _DashboardMenu.profile: return _MobileProfileView(isDark: _isDark);
      }
    }
    switch (_selectedMenu) {
      case _DashboardMenu.dashboard: return _DashboardOverview(isDark: _isDark, isMobile: isMobile, userRole: userRole);
      case _DashboardMenu.devices: return SingleChildScrollView(child: _DevicesList(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, isMobile: isMobile, userRole: userRole));
      case _DashboardMenu.apps: return SingleChildScrollView(child: _AppControls(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.schedules: return SingleChildScrollView(child: _SchedulesView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.location: return _LocationView(isDark: _isDark, textColor: textColor, onBack: () => _setSelectedMenu(_DashboardMenu.dashboard));
      case _DashboardMenu.monitoring: return _MonitoringView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, isMobile: isMobile);
      case _DashboardMenu.reports: return SingleChildScrollView(child: _ReportsView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.subscriptions: return SingleChildScrollView(child: _SubscriptionView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, userRole: userRole));
      case _DashboardMenu.paymentMethods: return SingleChildScrollView(child: _PaymentMethodsView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.pendingTransactions: return SingleChildScrollView(child: _PendingTransactionsView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.settings: return SingleChildScrollView(child: _SettingsView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.users: return SingleChildScrollView(child: _UsersList(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, isMobile: isMobile));
      case _DashboardMenu.profile: return SingleChildScrollView(child: _ProfileView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
    }
  }
}

class _Sidebar extends StatelessWidget {
  final _DashboardMenu selectedMenu; final Function(_DashboardMenu) onMenuSelected; final bool isCollapsed; final bool isDark; final String userRole;
  const _Sidebar({required this.selectedMenu, required this.onMenuSelected, required this.isCollapsed, required this.isDark, required this.userRole});
  
  Widget _buildSidebarItem(_DashboardMenu menu, String label, HeroIcons icon) {
    return _SidebarItem(icon: icon, label: label, isSelected: selectedMenu == menu, onTap: () => onMenuSelected(menu), isCollapsed: isCollapsed, isDark: isDark);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF0D0D10) : Colors.white; 
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300), width: isCollapsed ? 80 : 280, decoration: BoxDecoration(color: bgColor, border: const Border(right: BorderSide(color: Color(0xFF64748B), width: 0.5))),
      child: Column(children: [
        const SizedBox(height: 32), _buildBrand(), const SizedBox(height: 32),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          if (!isCollapsed) Padding(padding: const EdgeInsets.only(left: 12, bottom: 16), child: Text('MAIN MENU', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 2))),
          _buildSidebarItem(_DashboardMenu.dashboard, 'Dashboard', HeroIcons.squares2x2),
          _buildSidebarItem(_DashboardMenu.devices, userRole == 'super_admin' ? 'Global Devices' : 'My Devices', HeroIcons.devicePhoneMobile),
          if (userRole == 'super_admin') _buildSidebarItem(_DashboardMenu.users, 'Users Admin', HeroIcons.users),
          _buildSidebarItem(_DashboardMenu.apps, 'App Controls', HeroIcons.shieldCheck),
          _buildSidebarItem(_DashboardMenu.schedules, 'Schedules', HeroIcons.calendar),
          _buildSidebarItem(_DashboardMenu.location, 'Family Location', HeroIcons.mapPin),
          _buildSidebarItem(_DashboardMenu.monitoring, 'Activity Overview', HeroIcons.magnifyingGlassCircle),
          _buildSidebarItem(_DashboardMenu.reports, 'Activity Reports', HeroIcons.chartBar),
          _buildSidebarItem(_DashboardMenu.subscriptions, 'Subscription', HeroIcons.creditCard),
          if (userRole == 'super_admin') _buildSidebarItem(_DashboardMenu.paymentMethods, 'Payment Methods', HeroIcons.creditCard),
          if (userRole == 'super_admin') _buildSidebarItem(_DashboardMenu.pendingTransactions, 'Pending Payments', HeroIcons.documentCheck),
          _buildSidebarItem(_DashboardMenu.settings, 'Settings', HeroIcons.cog6Tooth),
          _buildSidebarItem(_DashboardMenu.profile, 'My Profile', HeroIcons.user),
        ])),
        Padding(padding: const EdgeInsets.all(16.0), child: _SidebarItem(icon: HeroIcons.arrowLeftOnRectangle, label: 'Logout', isSelected: false, onTap: () => FirebaseAuth.instance.signOut(), color: Colors.redAccent, isCollapsed: isCollapsed, isDark: isDark)),
        const SizedBox(height: 16),
      ]),
    );
  }
  Widget _buildBrand() { return Row(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]), child: const Icon(Icons.security_rounded, color: Colors.white, size: 22)), if (!isCollapsed) ...[const SizedBox(width: 14), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('AppLocker', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.5, color: isDark ? Colors.white : const Color(0xFF1E293B))), Text('PARENTAL CONTROL', style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.w900, color: const Color(0xFF6366F1), letterSpacing: 1.5))]) ]]); }
}

class _SidebarItem extends StatelessWidget {
  final HeroIcons icon; final String label; final bool isSelected; final VoidCallback onTap; final Color? color; final bool isCollapsed; final bool isDark;
  const _SidebarItem({required this.icon, required this.label, required this.isSelected, required this.onTap, this.color, required this.isCollapsed, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? const Color(0xFF6366F1); final baseColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), decoration: BoxDecoration(color: isSelected ? activeColor.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(14), border: isSelected ? Border.all(color: activeColor.withOpacity(0.2)) : null), child: Row(children: [HeroIcon(icon, size: 20, color: isSelected ? activeColor : baseColor, style: isSelected ? HeroIconStyle.solid : HeroIconStyle.outline), if (!isCollapsed) ...[const SizedBox(width: 14), Expanded(child: Text(label, style: GoogleFonts.outfit(fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? activeColor : baseColor)))]]))));
  }
}

class _Header extends StatelessWidget {
  final String title; final VoidCallback onMenuPressed; final bool isDark; final VoidCallback onThemeToggle; final bool isMobile;
  final String userRole; final VoidCallback? onAdminBadgeTap;
  const _Header({required this.title, required this.onMenuPressed, required this.isDark, required this.onThemeToggle, required this.isMobile, this.userRole = 'parent', this.onAdminBadgeTap});
  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF0D0D10) : Colors.white; final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    return Container(
      height: isMobile ? 70 : 80, padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24), decoration: BoxDecoration(color: bgColor, border: const Border(bottom: BorderSide(color: Color(0xFF64748B), width: 0.5))),
      child: Row(children: [
        IconButton(onPressed: onMenuPressed, icon: Icon(isMobile ? Icons.menu_rounded : Icons.menu_open_rounded, color: const Color(0xFF6366F1))), const SizedBox(width: 8), 
        if (!isMobile) Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)), 
        const Spacer(), 
        IconButton(onPressed: onThemeToggle, icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined, color: const Color(0xFF94A3B8), size: 20)), 
        const SizedBox(width: 12), 
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
          builder: (context, snapshot) {
            String plan = 'FREE';
            bool isAdmin = false;
            if (snapshot.hasData && snapshot.data?.data() != null) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              final role = (data['role'] ?? '').toString();
              isAdmin = role == 'super_admin';
              plan = isAdmin ? 'ADMIN' : (data['plan'] ?? 'FREE').toString().toUpperCase();
            }
            final badgeColor = isAdmin ? const Color(0xFFEF4444) : const Color(0xFF6366F1);
            final badge = Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), 
              decoration: BoxDecoration(color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), 
              child: Row(
                children: [
                  Icon(isAdmin ? Icons.admin_panel_settings_rounded : Icons.workspace_premium_rounded, size: 16, color: badgeColor), 
                  const SizedBox(width: 6), 
                  Text(plan, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: badgeColor)),
                ]
              )
            );
            if (isAdmin && onAdminBadgeTap != null) {
              return GestureDetector(onTap: onAdminBadgeTap, child: badge);
            }
            return badge;
          }
        ),
        if (!isMobile) ...[
          const SizedBox(width: 16),
          _buildAdminSelector(context),
        ]
      ]),
    );
  }

  Widget _buildAdminSelector(BuildContext context) { 
    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      elevation: 8,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF64748B), width: 0.5)),
      color: isDark ? const Color(0xFF18181B) : Colors.white,
      onSelected: (value) {
        if (value == 'edit') {
           _showEditProfile(context);
        } else if (value == 'logo') {
           _showUploadLogo(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF6366F1)), const SizedBox(width: 12), Text('Edit Profile', style: GoogleFonts.outfit(fontSize: 14))]),
        ),
        PopupMenuItem(
          value: 'logo',
          child: Row(children: [const Icon(Icons.add_photo_alternate_outlined, size: 18, color: Color(0xFF6366F1)), const SizedBox(width: 12), Text('Upload Logo', style: GoogleFonts.outfit(fontSize: 14))]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(children: [const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent), const SizedBox(width: 12), Text('Logout', style: GoogleFonts.outfit(fontSize: 14, color: Colors.redAccent))]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
        decoration: BoxDecoration(color: isDark ? const Color(0xFF18181B) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF64748B), width: 0.5)), 
        child: Row(children: [
          Container(padding: const EdgeInsets.all(1.5), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF6366F1), width: 1.5)), child: const CircleAvatar(radius: 12, backgroundColor: Colors.white, child: Icon(Icons.person, size: 16, color: Color(0xFF6366F1)))), 
          const SizedBox(width: 10), 
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
            builder: (context, snapshot) {
              String roleText = 'Admin';
              if (snapshot.hasData && snapshot.data!.data() != null) {
                final Map<String, dynamic> data = snapshot.data!.data() as Map<String, dynamic>;
                roleText = (data['role'] ?? 'admin').toString().replaceAll('_', ' ').toUpperCase();
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(roleText, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B))), 
                Text('Main Account', style: GoogleFonts.outfit(fontSize: 9, color: const Color(0xFF94A3B8)))
              ]);
            }
          ), 
          const SizedBox(width: 8),
          const Icon(Icons.unfold_more_rounded, size: 14, color: Color(0xFF94A3B8))
        ])
      ),
    ); 
  }

  void _showEditProfile(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF64748B), width: 0.5)),
        title: Text('Edit Profile', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF1E293B))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             TextField(decoration: InputDecoration(labelText: 'Full Name', hintText: 'Parent Admin', labelStyle: GoogleFonts.outfit(), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
             const SizedBox(height: 16),
             TextField(decoration: InputDecoration(labelText: 'Email Address', hintText: 'admin@applocker.com', labelStyle: GoogleFonts.outfit(), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
          ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text('Save Changes', style: GoogleFonts.outfit(color: Colors.white))),
        ],
      ),
    );
  }

  void _showUploadLogo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
         backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF64748B), width: 0.5)),
         title: Text('Upload Branding', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF1E293B))),
         content: Container(
           height: 180,
           width: 320,
           decoration: BoxDecoration(
             color: const Color(0xFF6366F1).withOpacity(0.05),
             borderRadius: BorderRadius.circular(20),
           border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.5), width: 2, style: BorderStyle.solid), // In real app, make it dashed
           ),
           child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               const Icon(Icons.cloud_upload_rounded, size: 54, color: Color(0xFF6366F1)),
               const SizedBox(height: 16),
               Text('DRAG & DROP BRANDING CONTENT', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: const Color(0xFF6366F1))),
               const SizedBox(height: 4),
               Text('Supports PNG, JPG (SVG recommended)', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8))),
             ],
           ),
         ),
         actions: [
           TextButton(onPressed: () => Navigator.pop(context), child: Text('Close Window', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
         ],
      ),
    );
  }
}

class _DashboardOverview extends StatelessWidget {
  final bool isDark; final bool isMobile; final String userRole;
  const _DashboardOverview({required this.isDark, required this.isMobile, required this.userRole});
  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final cardColor = isDark ? const Color(0xFF18181B) : Colors.white;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        if (userRole == 'super_admin') {
          return _SuperAdminDashboard(isDark: isDark, isMobile: isMobile);
        }

        int totalDevices = 0, onlineDevices = 0, offlineDevices = 0, totalAppsCount = 0;
        List<QueryDocumentSnapshot> docs = [];
        if (snapshot.hasData) {
          docs = snapshot.data!.docs;
          totalDevices = docs.length;
          final Set<String> uniquePackages = {};

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] ?? 'offline';
            if (status == 'online') onlineDevices++; else offlineDevices++;
            
            final installedApps = data['installedApps'] as List<dynamic>? ?? [];
            for (var app in installedApps) {
              if (app is Map) {
                final pkg = (app['packageName'] ?? app['pkg'] ?? '').toString();
                if (pkg.isNotEmpty) uniquePackages.add(pkg);
              }
            }
          }
          totalAppsCount = uniquePackages.length;
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              // 1. Parental Glass Header
              _buildParentalHeader(totalDevices, onlineDevices, textColor, cardColor),
              const SizedBox(height: 32),

              // 2. Metrics Grid
              _buildParentalMetrics(totalDevices, onlineDevices, offlineDevices, totalAppsCount, textColor),
              const SizedBox(height: 48),

              // 3. Charts Section
              if (isMobile) 
                Column(children: [
                  _buildLineChartCard(docs, textColor, isMobile, isDark),
                  const SizedBox(height: 24),
                  _buildPieChartCard(docs, textColor, isMobile, isDark),
                ])
              else 
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: _buildLineChartCard(docs, textColor, isMobile, isDark)),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: _buildPieChartCard(docs, textColor, isMobile, isDark)),
                ]),
              
              const SizedBox(height: 48),

              // 4. Action Button (Mobile Only)
              if (isMobile) 
                ElevatedButton.icon(
                  onPressed: () => showAppLockerPairingDialog(context, cardColor, textColor), 
                  icon: const Icon(Icons.add_rounded), 
                  label: const Text('Pair New Device'), 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1), 
                    foregroundColor: Colors.white, 
                    minimumSize: const Size(double.infinity, 60), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                  )
                ),
              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }

  Widget _buildParentalHeader(int total, int online, Color textColor, Color cardColor) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 24 : 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF6366F1).withOpacity(0.1) : const Color(0xFF6366F1).withOpacity(0.05),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Parental Suite', style: GoogleFonts.outfit(fontSize: isMobile ? 24 : 32, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -1)),
                const SizedBox(height: 4),
                Text('Currently protecting $total devices with $online online.', style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF94A3B8))),
              ],
            ),
          ),
          if (!isMobile) 
             Builder(builder: (context) => ElevatedButton.icon(
                onPressed: () => showAppLockerPairingDialog(context, cardColor, textColor), 
                icon: const Icon(Icons.add_rounded), 
                label: const Text('Pair New Device'), 
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1), 
                  foregroundColor: Colors.white, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)
                )
             )),
        ],
      ),
    );
  }

  Widget _buildParentalMetrics(int total, int online, int offline, int apps, Color textColor) {
    return LayoutBuilder(builder: (context, constraints) {
      int count = constraints.maxWidth < 600 ? 2 : 4;
      return GridView.count(
        crossAxisCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: constraints.maxWidth < 600 ? 1.4 : 1.8,
        children: [
          _StatCard(title: 'Devices', value: total.toString(), icon: HeroIcons.devicePhoneMobile, color: const Color(0xFF6366F1), isDark: isDark),
          _StatCard(title: 'Online', value: online.toString(), icon: HeroIcons.signal, color: const Color(0xFF10B981), isDark: isDark),
          _StatCard(title: 'Offline', value: offline.toString(), icon: HeroIcons.noSymbol, color: const Color(0xFFEF4444), isDark: isDark),
          _StatCard(title: 'Apps Clean', value: apps.toString(), icon: HeroIcons.shieldCheck, color: const Color(0xFF6366F1), isDark: isDark),
        ],
      );
    });
  }
  List<Widget> _buildStatCards(int total, int online, int offline, int blocked, int hidden, int totalApps) { 
    return [
      _StatCard(title: 'Total Devices', value: total.toString(), icon: HeroIcons.devicePhoneMobile, color: const Color(0xFF6366F1), isDark: isDark),
      _StatCard(title: 'Online', value: online.toString(), icon: HeroIcons.signal, color: const Color(0xFF10B981), isDark: isDark),
      _StatCard(title: 'Offline', value: offline.toString(), icon: HeroIcons.noSymbol, color: const Color(0xFFEF4444), isDark: isDark),
      _StatCard(title: 'Restricted Apps', value: blocked.toString(), icon: HeroIcons.shieldExclamation, color: const Color(0xFFF59E0B), isDark: isDark),
      _StatCard(title: 'Filtered Apps', value: hidden.toString(), icon: HeroIcons.eyeSlash, color: const Color(0xFF8B5CF6), isDark: isDark),
      _StatCard(title: 'Total Apps', value: totalApps.toString(), icon: HeroIcons.squaresPlus, color: const Color(0xFFEC4899), isDark: isDark),
    ]; 
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE TOP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _MobileTopBar extends StatelessWidget {
  final String title;
  final bool isDark;
  final VoidCallback onThemeToggle;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final String userRole;

  const _MobileTopBar({
    required this.title,
    required this.isDark,
    required this.onThemeToggle,
    this.onPrev,
    this.onNext,
    this.userRole = 'parent',
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white70 : const Color(0xFF64748B);
    final isAdmin = userRole == 'super_admin';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: onPrev,
            child: Icon(Icons.chevron_left_rounded,
                color: onPrev != null ? textColor : textColor.withOpacity(0.2),
                size: 28),
          ),
          const SizedBox(width: 4),
          if (isAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.admin_panel_settings_rounded, size: 14, color: Color(0xFFEF4444)),
                const SizedBox(width: 4),
                Text('ADMIN', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFFEF4444))),
              ]),
            ),
          const Spacer(),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onThemeToggle,
            child: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
              color: textColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onNext,
            child: Icon(Icons.chevron_right_rounded,
                color: onNext != null ? textColor : textColor.withOpacity(0.2),
                size: 28),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE DASHBOARD HOME (new design matching the image)
// ─────────────────────────────────────────────────────────────────────────────
class _MobileDashboardHome extends StatefulWidget {
  final bool isDark;
  final String userRole;
  final Function(_DashboardMenu)? onNavigate;
  const _MobileDashboardHome({required this.isDark, required this.userRole, this.onNavigate});
  @override
  State<_MobileDashboardHome> createState() => _MobileDashboardHomeState();
}

class _MobileDashboardHomeState extends State<_MobileDashboardHome> with TickerProviderStateMixin {
  late final AnimationController _ctrlRing1;
  late final AnimationController _ctrlRing2;
  late final AnimationController _ctrlRing3;

  @override
  void initState() {
    super.initState();
    _ctrlRing1 = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _ctrlRing2 = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _ctrlRing3 = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() {
    _ctrlRing1.dispose();
    _ctrlRing2.dispose();
    _ctrlRing3.dispose();
    super.dispose();
  }

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        int totalDevices = 0, onlineDevices = 0, offlineDevices = 0, totalApps = 0;
        List<QueryDocumentSnapshot> docs = [];
        if (snapshot.hasData) {
          docs = snapshot.data!.docs;
          totalDevices = docs.length;
          final Set<String> pkgs = {};
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            if ((data['status'] ?? 'offline') == 'online') {
              onlineDevices++;
            } else {
              offlineDevices++;
            }
            for (var app in (data['installedApps'] as List<dynamic>? ?? [])) {
              if (app is Map) {
                final pkg = (app['packageName'] ?? app['pkg'] ?? '').toString();
                if (pkg.isNotEmpty) pkgs.add(pkg);
              }
            }
          }
          totalApps = pkgs.length;
        }

        final bg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF0F4FF);
        final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);

        return Container(
          color: bg,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                // ── Circular Gauge (animated rings) ──
                SizedBox(
                  height: 260,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_ctrlRing1, _ctrlRing2, _ctrlRing3]),
                      builder: (_, __) => CustomPaint(
                        size: const Size(220, 220),
                        painter: _GaugePainter(
                          isDark: widget.isDark,
                          value: totalApps,
                          total: max(totalApps, 1),
                          rotAngle1: _ctrlRing1.value * 2 * pi,
                          rotAngle2: -(_ctrlRing2.value * 2 * pi),
                          rotAngle3: _ctrlRing3.value * 2 * pi,
                        ),
                        child: SizedBox(
                          width: 220,
                          height: 220,
                          child: Center(
                            child: Text(
                              _formatCount(totalApps),
                              style: GoogleFonts.outfit(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: widget.isDark ? Colors.white : const Color(0xFF1E293B),
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                // ── Quick Stat Buttons ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _MobileQuickStat(
                        icon: Icons.phone_android_rounded,
                        label: 'Devices',
                        value: totalDevices,
                        iconColor: const Color(0xFF38BDF8),
                        isDark: widget.isDark,
                      ),
                      _MobileQuickStat(
                        icon: Icons.wifi_rounded,
                        label: 'Online',
                        value: onlineDevices,
                        iconColor: const Color(0xFF34D399),
                        isDark: widget.isDark,
                      ),
                      _MobileQuickStat(
                        icon: Icons.remove_circle_outline_rounded,
                        label: 'Offline',
                        value: offlineDevices,
                        iconColor: const Color(0xFFF87171),
                        isDark: widget.isDark,
                      ),
                      _MobileQuickStat(
                        icon: Icons.apps_rounded,
                        label: 'Apps',
                        value: totalApps,
                        iconColor: const Color(0xFFA78BFA),
                        isDark: widget.isDark,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ── Latest Devices heading ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'Latest Devices',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      Builder(builder: (ctx) => GestureDetector(
                        onTap: () {
                          final cardColor = widget.isDark ? const Color(0xFF18181B) : Colors.white;
                          showAppLockerPairingDialog(ctx, cardColor, textColor);
                        },
                        child: Row(
                          children: [
                            Container(
                              width: 26, height: 26,
                              decoration: BoxDecoration(color: const Color(0xFF6366F1), shape: BoxShape.circle),
                              child: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                            ),
                            const SizedBox(width: 6),
                            Text('Add New Device', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF6366F1))),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Device Cards ──
                if (docs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                    child: Text(
                      'No devices paired yet.\nPair a device to get started.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: widget.isDark ? Colors.white38 : const Color(0xFF94A3B8),
                        height: 1.6,
                      ),
                    ),
                  )
                else
                  ...docs.take(6).map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    // Match same field priority as the Devices page
                    final rawName = data['model'] ?? data['deviceName'] ?? data['name'] ?? data['brand'] ?? '';
                    final name = rawName.toString().trim().isEmpty ? doc.id : rawName.toString().trim();
                    final status = data['status'] ?? 'offline';
                    final battery = data['battery'] ?? data['batteryLevel'] ?? 0;
                    final lastSeen = data['lastSeen'] as Timestamp?;
                    final isOnline = status == 'online';

                    String timeLabel;
                    if (lastSeen != null) {
                      final diff = DateTime.now().difference(lastSeen.toDate());
                      if (diff.inSeconds < 60) {
                        timeLabel = isOnline ? 'Active: Just now' : 'Last Sync: ${diff.inSeconds}s ago';
                      } else if (diff.inMinutes < 60) {
                        timeLabel = isOnline ? 'Active: ${diff.inMinutes}m ago' : 'Last Sync: ${diff.inMinutes}m ago';
                      } else if (diff.inHours < 24) {
                        timeLabel = 'Last Sync: ${diff.inHours}h ago';
                      } else if (diff.inDays < 7) {
                        timeLabel = 'Last Sync: ${diff.inDays}d ago';
                      } else {
                        timeLabel = 'Last Sync: ${DateFormat('MMM d').format(lastSeen.toDate())}';
                      }
                    } else if (isOnline) {
                      timeLabel = 'Active: Online now';
                    } else {
                      timeLabel = 'Last Sync: Unknown';
                    }

                    final lockSchedules = (data['lockSchedules'] as List?)
                        ?.whereType<Map>()
                        .toList() ?? [];
                    final hasScheduledLock = lockSchedules.any(
                      (s) => s['enabled'] != false,
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: _MobileDeviceCard(
                        name: name,
                        deviceId: doc.id,
                        status: status,
                        battery: battery is int ? battery : (battery as num).toInt(),
                        timeLabel: timeLabel,
                        isOnline: isOnline,
                        isDark: widget.isDark,
                        hasScheduledLock: hasScheduledLock,
                        onTap: () => widget.onNavigate?.call(_DashboardMenu.devices),
                      ),
                    );
                  }),

                const SizedBox(height: 16),

                // ── Pair button ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Builder(builder: (ctx) => GestureDetector(
                    onTap: () {
                      final cardColor = widget.isDark ? const Color(0xFF18181B) : Colors.white;
                      showAppLockerPairingDialog(ctx, cardColor, textColor);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_circle_outline_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Pair New Device',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GAUGE PAINTER — three concentric gradient arcs + tick marks
// ─────────────────────────────────────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final bool isDark;
  final int value;
  final int total;
  final double rotAngle1;
  final double rotAngle2;
  final double rotAngle3;

  const _GaugePainter({
    required this.isDark,
    required this.value,
    required this.total,
    this.rotAngle1 = 0,
    this.rotAngle2 = 0,
    this.rotAngle3 = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);

    final r1 = size.width * 0.43;
    final r2 = size.width * 0.33;
    final r3 = size.width * 0.23;

    const double fullSweep = pi * 1.56;

    final trackColor = isDark ? const Color(0xFF131D3B) : const Color(0xFFDDE3F0);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = trackColor;

    canvas.drawCircle(center, r1, trackPaint..strokeWidth = 11);
    canvas.drawCircle(center, r2, trackPaint..strokeWidth = 9);
    canvas.drawCircle(center, r3, trackPaint..strokeWidth = 7);

    void drawGradientArc(double radius, double sweep, double strokeW,
        List<Color> colors, List<double> stops, double rotOffset) {
      final startAngle = pi * 0.82 + rotOffset;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: colors,
          stops: stops,
          startAngle: startAngle,
          endAngle: startAngle + fullSweep,
          transform: GradientRotation(0),
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.5));
      canvas.drawArc(rect, startAngle, sweep, false, paint);
    }

    drawGradientArc(r1, fullSweep, 11,
        [const Color(0xFF7C3AED), const Color(0xFF6366F1), const Color(0xFF38BDF8)],
        [0.0, 0.5, 1.0], rotAngle1);
    drawGradientArc(r2, fullSweep * 0.72, 9,
        [const Color(0xFF4F46E5), const Color(0xFF818CF8)],
        [0.0, 1.0], rotAngle2);
    drawGradientArc(r3, fullSweep * 0.48, 7,
        [const Color(0xFF7C3AED), const Color(0xFFA78BFA)],
        [0.0, 1.0], rotAngle3);

    // Tick marks at the bottom
    final tickPaint = Paint()
      ..color = isDark ? const Color(0xFF2D3A6B) : const Color(0xFFBBC8E0)
      ..style = PaintingStyle.fill;

    const int tickCount = 7;
    const double tickCenterAngle = pi / 2;
    const double tickSpread = pi * 0.38;
    final double tickStartA = tickCenterAngle - tickSpread / 2;
    final double tickR = r1 * 1.12;

    for (int i = 0; i < tickCount; i++) {
      final angle = tickStartA + (i * tickSpread / (tickCount - 1));
      final tx = cx + tickR * cos(angle);
      final ty = cy + tickR * sin(angle);
      canvas.save();
      canvas.translate(tx, ty);
      canvas.rotate(angle + pi / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 5, height: 14),
          const Radius.circular(3),
        ),
        tickPaint..color = i == tickCount ~/ 2
            ? const Color(0xFF6366F1)
            : (isDark ? const Color(0xFF2D3A6B) : const Color(0xFFBBC8E0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.isDark != isDark ||
      old.rotAngle1 != rotAngle1 || old.rotAngle2 != rotAngle2 || old.rotAngle3 != rotAngle3;
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE QUICK STAT BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _MobileQuickStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color iconColor;
  final bool isDark;
  const _MobileQuickStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0F1A35) : const Color(0xFFE8EFFF);
    final labelColor = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: iconColor.withOpacity(0.25),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            Positioned(
              top: -6,
              right: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: iconColor.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Text(
                  value.toString(),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: labelColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE DEVICE CARD — gradient background matching the design
// ─────────────────────────────────────────────────────────────────────────────
class _MobileDeviceCard extends StatefulWidget {
  final String name;
  final String deviceId;
  final String status;
  final int battery;
  final String timeLabel;
  final bool isOnline;
  final bool isDark;
  final bool hasScheduledLock;
  final VoidCallback? onTap;

  const _MobileDeviceCard({
    required this.name,
    required this.deviceId,
    required this.status,
    required this.battery,
    required this.timeLabel,
    required this.isOnline,
    required this.isDark,
    this.hasScheduledLock = false,
    this.onTap,
  });

  @override
  State<_MobileDeviceCard> createState() => _MobileDeviceCardState();
}

class _MobileDeviceCardState extends State<_MobileDeviceCard> {
  int _unreadCount = 0;
  late final Stream<QuerySnapshot> _msgStream;

  @override
  void initState() {
    super.initState();
    _msgStream = FirebaseFirestore.instance
        .collection('devices')
        .doc(widget.deviceId)
        .collection('messages')
        .where('sender', isEqualTo: 'child')
        .where('read', isEqualTo: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = widget.isOnline
        ? const LinearGradient(
            colors: [Color(0xFF6D28D9), Color(0xFF4338CA)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : const LinearGradient(
            colors: [Color(0xFFEA580C), Color(0xFFF59E0B)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          );

    return StreamBuilder<QuerySnapshot>(
      stream: _msgStream,
      builder: (context, snap) {
        final unread = snap.data?.docs.length ?? _unreadCount;
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: (widget.isOnline ? const Color(0xFF6D28D9) : const Color(0xFFEA580C))
                      .withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: widget.isOnline ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isOnline ? 'Online' : 'Offline',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (widget.hasScheduledLock) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.schedule_rounded, size: 11, color: Colors.white60),
                          const SizedBox(width: 3),
                          Text('Scheduled', style: GoogleFonts.outfit(fontSize: 10, color: Colors.white60)),
                        ],
                      ]),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (unread > 0) ...[
                        Stack(children: [
                          const Icon(Icons.chat_bubble_rounded, color: Colors.white70, size: 18),
                          Positioned(top: 0, right: 0, child: Container(
                            width: 10, height: 10,
                            decoration: const BoxDecoration(color: Color(0xFFFBBF24), shape: BoxShape.circle),
                            child: Center(child: Text(unread > 9 ? '9+' : '$unread',
                              style: const TextStyle(color: Colors.black, fontSize: 6, fontWeight: FontWeight.bold))),
                          )),
                        ]),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${widget.battery}%',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      widget.timeLabel,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE BOTTOM NAV
// ─────────────────────────────────────────────────────────────────────────────
class _MobileBottomNav extends StatelessWidget {
  final _DashboardMenu selected;
  final bool isDark;
  final Function(_DashboardMenu) onSelected;
  final VoidCallback onMorePressed;

  const _MobileBottomNav({
    required this.selected,
    required this.isDark,
    required this.onSelected,
    required this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF080F22) : Colors.white;
    final activeColor = const Color(0xFF818CF8);
    final inactiveColor = isDark ? Colors.white38 : const Color(0xFF94A3B8);

    final items = [
      (_DashboardMenu.dashboard, Icons.home_rounded, 'Home'),
      (_DashboardMenu.devices, Icons.phone_android_rounded, 'Devices'),
      (_DashboardMenu.apps, Icons.shield_rounded, 'Apps'),
      (_DashboardMenu.schedules, Icons.schedule_rounded, 'Schedule'),
    ];

    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07), width: 1)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, -4))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          ...items.map((item) {
            final isActive = selected == item.$1;
            return GestureDetector(
              onTap: () => onSelected(item.$1),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 60,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isActive ? activeColor.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.$2,
                          color: isActive ? activeColor : inactiveColor,
                          size: 22),
                    ),
                    const SizedBox(height: 2),
                    Text(item.$3,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                          color: isActive ? activeColor : inactiveColor,
                        )),
                  ],
                ),
              ),
            );
          }),
          GestureDetector(
            onTap: onMorePressed,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.more_horiz_rounded,
                        color: inactiveColor, size: 22),
                  ),
                  const SizedBox(height: 2),
                  Text('More',
                      style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: inactiveColor)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE MORE SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _MobileMoreSheet extends StatelessWidget {
  final bool isDark;
  final _DashboardMenu selectedMenu;
  final Function(_DashboardMenu) onMenuSelected;
  final String userRole;

  const _MobileMoreSheet({
    required this.isDark,
    required this.selectedMenu,
    required this.onMenuSelected,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0D1530) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtextColor = isDark ? Colors.white54 : const Color(0xFF94A3B8);

    final moreItems = <(_DashboardMenu, IconData, String, String, Color)>[
      if (userRole == 'super_admin') ...[
        (_DashboardMenu.users, Icons.admin_panel_settings_rounded, 'Users Admin', 'Global user management', const Color(0xFFEF4444)),
        (_DashboardMenu.paymentMethods, Icons.credit_card_rounded, 'Payment Methods', 'Manage payment options', const Color(0xFF6366F1)),
        (_DashboardMenu.pendingTransactions, Icons.pending_actions_rounded, 'Pending Payments', 'Approve transactions', const Color(0xFF22C55E)),
      ],
      (_DashboardMenu.location, Icons.location_on_rounded, 'Location', 'View child location', const Color(0xFF10B981)),
      (_DashboardMenu.monitoring, Icons.monitor_heart_rounded, 'Activity', 'Child activity logs', const Color(0xFF6366F1)),
      (_DashboardMenu.reports, Icons.bar_chart_rounded, 'Reports', 'Usage statistics', const Color(0xFFF59E0B)),
      (_DashboardMenu.subscriptions, Icons.workspace_premium_rounded, 'Subscription', 'Plan & billing', const Color(0xFFEC4899)),
      (_DashboardMenu.settings, Icons.settings_rounded, 'Settings', 'App configuration', const Color(0xFF94A3B8)),
      (_DashboardMenu.profile, Icons.person_rounded, 'My Profile', 'Manage your account', const Color(0xFF6366F1)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'More Options',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...moreItems.map((item) {
                    final isActive = selectedMenu == item.$1;
                    return GestureDetector(
                      onTap: () => onMenuSelected(item.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isActive
                              ? item.$5.withOpacity(0.12)
                              : (isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive ? item.$5.withOpacity(0.3) : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: item.$5.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(item.$2, color: item.$5, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.$3,
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: isActive ? item.$5 : textColor,
                                    )),
                                Text(item.$4,
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      color: subtextColor,
                                    )),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: isActive ? item.$5 : subtextColor, size: 18),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      FirebaseAuth.instance.signOut();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.transparent),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Logout',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.redAccent,
                                  )),
                              Text('Sign out of your account',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: subtextColor,
                                  )),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: Colors.redAccent, size: 18),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MOBILE PAGE VIEWS — Devices, Chat, Schedules, Apps, Location,
//                     Monitoring, Reports, Subscriptions, Settings
// ═══════════════════════════════════════════════════════════════════════════

// ─── Devices ────────────────────────────────────────────────────────────────
class _MobileDevicesView extends StatefulWidget {
  final bool isDark; final String userRole;
  final Function(_DashboardMenu)? onNavigate;
  const _MobileDevicesView({required this.isDark, required this.userRole, this.onNavigate});
  @override State<_MobileDevicesView> createState() => _MobileDevicesViewState();
}
class _MobileDevicesViewState extends State<_MobileDevicesView> {
  void _openChat(BuildContext context, String deviceId) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _MobileChatSheet(deviceId: deviceId, isDark: widget.isDark));
  }
  Future<void> _toggleLock(String deviceId, bool current) async =>
      FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'locked': !current});

  void _openScheduleDialog(BuildContext context, String deviceId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleLockSheet(deviceId: deviceId, deviceData: data, isDark: widget.isDark),
    );
  }

  Future<void> _removeDevice(BuildContext context, String deviceId) async {
    final bg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove Device?', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor)),
        content: Text('This will unlink the device and remove all its settings.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Remove', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('devices').doc(deviceId).delete();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device removed.'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    final cardColor = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snap.data!.docs;
        return Container(
          color: bg,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Device list', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
                const Spacer(),
                // Add new device
                GestureDetector(
                  onTap: () => showAppLockerPairingDialog(context, cardColor, textColor),
                  child: Container(
                    width: 30, height: 30,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: const BoxDecoration(color: Color(0xFF6366F1), shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                  ),
                ),
                // Back → Dashboard
                GestureDetector(
                  onTap: () => widget.onNavigate?.call(_DashboardMenu.dashboard),
                  child: Row(children: [
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF6366F1)),
                    const SizedBox(width: 4),
                    Text('Back', style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF6366F1), fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              if (devices.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No devices paired yet.', style: GoogleFonts.outfit(color: widget.isDark ? Colors.white38 : const Color(0xFF94A3B8))))),
              ...devices.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final isOnline = (data['status'] ?? 'offline') == 'online';
                final battery = ((data['battery'] ?? 0) as num).toInt();
                final isLocked = data['locked'] == true;
                final deviceName = (data['model'] ?? data['name'] ?? doc.id).toString();
                final latRaw = data['lat'] ?? data['latitude'];
                final lngRaw = data['lng'] ?? data['longitude'] ?? data['lon'];
                final lat = latRaw != null ? (latRaw as num).toDouble() : null;
                final lng = lngRaw != null ? (lngRaw as num).toDouble() : null;
                return _MobileDeviceListCard(
                  name: deviceName, deviceId: doc.id, isOnline: isOnline, battery: battery,
                  isDark: widget.isDark, isLocked: isLocked,
                  lat: lat, lng: lng,
                  onChat: () => _openChat(context, doc.id),
                  onLock: () => _toggleLock(doc.id, isLocked),
                  onLocation: () => widget.onNavigate?.call(_DashboardMenu.location),
                  onSchedule: () => _openScheduleDialog(context, doc.id, data),
                  onRemove: () => _removeDevice(context, doc.id),
                );
              }),
              const SizedBox(height: 12),
              Builder(builder: (ctx) => GestureDetector(
                onTap: () => showAppLockerPairingDialog(ctx, cardColor, textColor),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF6366F1)]), borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Text('+ Add New Device', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))),
                ),
              )),
            ]),
          ),
        );
      },
    );
  }
}

class _MobileDeviceListCard extends StatefulWidget {
  final String name; final String deviceId; final bool isOnline; final int battery; final bool isDark; final bool isLocked;
  final double? lat; final double? lng;
  final VoidCallback onChat; final VoidCallback onLock;
  final VoidCallback? onLocation; final VoidCallback? onSchedule; final VoidCallback? onRemove;
  const _MobileDeviceListCard({required this.name, required this.deviceId, required this.isOnline, required this.battery, required this.isDark, required this.isLocked, required this.onChat, required this.onLock, this.lat, this.lng, this.onLocation, this.onSchedule, this.onRemove});

  @override
  State<_MobileDeviceListCard> createState() => _MobileDeviceListCardState();
}

class _MobileDeviceListCardState extends State<_MobileDeviceListCard> {
  String? _locationName;
  bool _geocoding = false;
  late final Stream<QuerySnapshot> _msgStream;

  @override
  void initState() {
    super.initState();
    _msgStream = FirebaseFirestore.instance
        .collection('devices')
        .doc(widget.deviceId)
        .collection('messages')
        .where('sender', isEqualTo: 'child')
        .where('read', isEqualTo: false)
        .snapshots();
    _fetchLocationName();
  }

  @override
  void didUpdateWidget(_MobileDeviceListCard old) {
    super.didUpdateWidget(old);
    if (old.lat != widget.lat || old.lng != widget.lng) {
      _fetchLocationName();
    }
  }

  Future<void> _fetchLocationName() async {
    final lat = widget.lat;
    final lng = widget.lng;
    if (lat == null || lng == null) return;
    if (_geocoding) return;
    setState(() => _geocoding = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json',
      );
      final resp = await http.get(uri, headers: {'User-Agent': 'AppLockerDashboard/1.0'});
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final addr = json['address'] as Map<String, dynamic>? ?? {};
        final city = addr['city'] ?? addr['town'] ?? addr['municipality'] ?? addr['county'] ?? '';
        final suburb = addr['suburb'] ?? addr['village'] ?? addr['quarter'] ?? addr['neighbourhood'] ?? '';
        final parts = [suburb, city].where((s) => s.toString().isNotEmpty).toList();
        if (mounted) setState(() => _locationName = parts.isNotEmpty ? parts.join(', ') : null);
      }
    } catch (_) {}
    if (mounted) setState(() => _geocoding = false);
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor = widget.isDark ? Colors.white54 : const Color(0xFF64748B);
    final circleColor = widget.isOnline ? const Color(0xFF22C55E) : const Color(0xFF94A3B8);
    final borderColor = widget.isOnline ? const Color(0xFF22C55E).withOpacity(0.4) : const Color(0xFF94A3B8).withOpacity(0.3);
    final batColor = widget.battery > 50 ? const Color(0xFF22C55E) : widget.battery > 20 ? const Color(0xFFFBBF24) : const Color(0xFFEF4444);
    return StreamBuilder<QuerySnapshot>(
      stream: _msgStream,
      builder: (context, msgSnap) {
        final unread = msgSnap.data?.docs.length ?? 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 52, height: 52, decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
                child: const Icon(Icons.smartphone_rounded, color: Colors.white, size: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.battery_charging_full_rounded, size: 12, color: batColor), const SizedBox(width: 3), Text('${widget.battery}%', style: GoogleFonts.outfit(fontSize: 11, color: batColor, fontWeight: FontWeight.w700))]),
                const SizedBox(height: 2),
                Text(widget.name, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(widget.deviceId.length > 18 ? widget.deviceId.substring(0, 18) + '…' : widget.deviceId, style: GoogleFonts.outfit(fontSize: 10, color: subColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: widget.isOnline ? const Color(0xFF22C55E) : const Color(0xFF94A3B8), shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(widget.isOnline ? 'Online' : 'Offline', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: widget.isOnline ? const Color(0xFF22C55E) : const Color(0xFF94A3B8))),
                  if (_locationName != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.location_on_rounded, size: 10, color: Color(0xFFEF4444)),
                    const SizedBox(width: 2),
                    Flexible(child: Text(_locationName!, style: GoogleFonts.outfit(fontSize: 10, color: subColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ]),
              ])),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onLock,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: widget.isLocked ? const Color(0xFFEF4444).withOpacity(0.1) : const Color(0xFF22C55E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: widget.isLocked ? const Color(0xFFEF4444).withOpacity(0.4) : const Color(0xFF22C55E).withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(widget.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 14, color: widget.isLocked ? const Color(0xFFEF4444) : const Color(0xFF22C55E)),
                    const SizedBox(width: 4),
                    Text(widget.isLocked ? 'Locked' : 'Unlock', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: widget.isLocked ? const Color(0xFFEF4444) : const Color(0xFF22C55E))),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: widget.isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _DevActCircle(icon: Icons.location_on_rounded, color: const Color(0xFFEF4444), label: 'Location', onTap: widget.onLocation ?? () {}),
                Container(width: 1, height: 36, color: widget.isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                _DevActCircle(icon: Icons.chat_bubble_rounded, color: const Color(0xFFFBBF24), label: 'Chat', onTap: widget.onChat, badgeCount: unread),
                Container(width: 1, height: 36, color: widget.isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                _DevActCircle(icon: Icons.calendar_month_rounded, color: const Color(0xFF6366F1), label: 'Schedule', onTap: widget.onSchedule ?? () {}),
                Container(width: 1, height: 36, color: widget.isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                _DevActCircle(icon: Icons.delete_outline_rounded, color: const Color(0xFFEF4444), label: 'Remove', onTap: widget.onRemove ?? () {}),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _DevActCircle extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap; final int badgeCount; final String? label;
  const _DevActCircle({required this.icon, required this.color, required this.onTap, this.badgeCount = 0, this.label});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
        if (badgeCount > 0) Positioned(top: 0, right: 0, child: Container(
          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
          child: Center(child: Text(badgeCount > 9 ? '9+' : '$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold))))),
      ]),
      if (label != null) ...[const SizedBox(height: 3), Text(label!, style: GoogleFonts.outfit(fontSize: 9, color: color, fontWeight: FontWeight.w700))],
    ]),
  );
}

// ─── Chat Sheet ──────────────────────────────────────────────────────────────
class _MobileChatSheet extends StatefulWidget {
  final String deviceId; final bool isDark;
  const _MobileChatSheet({required this.deviceId, required this.isDark});
  @override State<_MobileChatSheet> createState() => _MobileChatSheetState();
}
class _MobileChatSheetState extends State<_MobileChatSheet> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    FirebaseService.instance.markMessagesRead(widget.deviceId, 'child');
  }

  @override void dispose() { _ctrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _send() async {
    final t = _ctrl.text.trim(); if (t.isEmpty) return; _ctrl.clear();
    await FirebaseService.instance.sendChatMessage(widget.deviceId, t, 'parent');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear Chat History?', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: widget.isDark ? Colors.white : const Color(0xFF1E293B))),
        content: Text('This will permanently delete all messages for both you and the child. This cannot be undone.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear All', style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await FirebaseService.instance.clearChatHistory(widget.deviceId);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to clear chat.'), backgroundColor: Color(0xFFEF4444)));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final bg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final msgAreaBg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFFAFAFA);
    return Container(
      margin: const EdgeInsets.fromLTRB(15, 0, 15, 15),
      height: h * 0.88,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.hardEdge,
      child: Column(children: [
        // ── Header ──
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
          decoration: const BoxDecoration(color: Color(0xFFFBBF24)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 24)),
            const SizedBox(width: 14),
            Text('Chat Now', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
            const Spacer(),
            GestureDetector(
              onTap: _clearing ? null : _clearChat,
              child: Container(
                width: 36, height: 36,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), shape: BoxShape.circle),
                child: _clearing
                    ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 20),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20)),
            ),
          ]),
        ),
        // ── Messages ──
        Expanded(child: Container(
          color: msgAreaBg,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.instance.streamChatMessages(widget.deviceId),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED)));
              final docs = snap.data!.docs;
              if (docs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFD1D5DB), size: 48),
                const SizedBox(height: 12),
                Text('No messages yet.\nSay hello to your child!', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
              ]));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
              });
              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final isParent = data['sender'] == 'parent';
                  final text = data['text'] as String? ?? '';
                  final ts = (data['timestamp'] as Timestamp?)?.toDate();
                  final timeStr = ts != null ? DateFormat('MMM d, yyyy h:mm a').format(ts) : '';
                  final maxW = MediaQuery.of(context).size.width * 0.58;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: isParent
                      ? Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.center, children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Text(timeStr, style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF94A3B8))),
                          ),
                          Container(
                            constraints: BoxConstraints(maxWidth: maxW),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9D5FF),
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(4)),
                            ),
                            child: Text(text, style: GoogleFonts.outfit(color: const Color(0xFF4C1D95), fontSize: 14, fontWeight: FontWeight.w500, height: 1.5)),
                          ),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.center, children: [
                          Container(
                            constraints: BoxConstraints(maxWidth: maxW),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomRight: Radius.circular(20), bottomLeft: Radius.circular(4)),
                            ),
                            child: Text(text, style: GoogleFonts.outfit(color: const Color(0xFF1E293B), fontSize: 14, fontWeight: FontWeight.w500, height: 1.5)),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(timeStr, style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF94A3B8))),
                          ),
                        ]),
                  );
                },
              );
            },
          ),
        )),
        // ── Input ──
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          decoration: BoxDecoration(
            color: bg,
            border: Border(top: BorderSide(color: widget.isDark ? Colors.white10 : const Color(0xFFE2E8F0))),
          ),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              onSubmitted: (_) => _send(),
              style: GoogleFonts.outfit(fontSize: 14, color: widget.isDark ? Colors.white : const Color(0xFF1E293B)),
              decoration: InputDecoration(
                hintText: 'Type a message...', hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                filled: true,
                fillColor: widget.isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: widget.isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5)),
              ),
            )),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 52, height: 52,
                decoration: const BoxDecoration(color: Color(0xFF7C3AED), shape: BoxShape.circle),
                child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 24),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Schedule Lock Sheet ─────────────────────────────────────────────────────
class _ScheduleLockSheet extends StatefulWidget {
  final String deviceId; final Map<String, dynamic> deviceData; final bool isDark;
  const _ScheduleLockSheet({required this.deviceId, required this.deviceData, required this.isDark});
  @override State<_ScheduleLockSheet> createState() => _ScheduleLockSheetState();
}
class _ScheduleLockSheetState extends State<_ScheduleLockSheet> {
  TimeOfDay _startTime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 6, minute: 0);
  bool _saving = false;

  // ── helpers ────────────────────────────────────────────────────────────────
  String _fmtTimeStore(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  String _to12h(String t24) {
    final parts = t24.split(':');
    if (parts.length < 2) return t24;
    int h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final period = h < 12 ? 'AM' : 'PM';
    h = h % 12; if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')} $period';
  }

  /// Returns true if the current time is inside the given start→end window.
  bool _isNowInWindow(String start24, String end24) {
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final sp = start24.split(':');
    final ep = end24.split(':');
    if (sp.length < 2 || ep.length < 2) return false;
    final startMin = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
    final endMin   = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
    // Handles overnight windows (e.g. 22:00 → 06:00)
    if (startMin <= endMin) return nowMin >= startMin && nowMin < endMin;
    return nowMin >= startMin || nowMin < endMin;
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1))), child: child!));
    if (picked != null) setState(() { if (isStart) _startTime = picked; else _endTime = picked; });
  }

  Future<void> _addSchedule(List<dynamic> currentSchedules) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final allowed = await PlanGate.requireForUser(
        context, uid, (f) => f.scheduleLock,
        featureLabel: 'Schedule Lock',
      );
      if (!allowed) return;
    }
    setState(() => _saving = true);
    try {
      final updated = List<dynamic>.from(currentSchedules)
        ..add({'start': _fmtTimeStore(_startTime), 'end': _fmtTimeStore(_endTime)});
      // Check if the new schedule is active right now — if so, lock immediately
      final activeNow = _isNowInWindow(_fmtTimeStore(_startTime), _fmtTimeStore(_endTime));
      final Map<String, dynamic> patch = {'lockSchedules': updated};
      if (activeNow) {
        patch['locked'] = true;
        patch['lockReason'] = 'Scheduled lock: ${_fmtTime(_startTime)} – ${_fmtTime(_endTime)}';
      }
      await FirebaseFirestore.instance.collection('devices').doc(widget.deviceId).update(patch);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(activeNow ? 'Schedule added & device locked now!' : 'Schedule added!'),
        backgroundColor: const Color(0xFF22C55E),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSchedule(List<dynamic> currentSchedules, int index) async {
    final schedule = Map<String, dynamic>.from(currentSchedules[index] as Map);
    final start24 = schedule['start'] as String? ?? '';
    final end24   = schedule['end']   as String? ?? '';
    final updated = List<dynamic>.from(currentSchedules)..removeAt(index);
    // If this schedule is currently active, also clear the lock
    final Map<String, dynamic> patch = {'lockSchedules': updated};
    if (_isNowInWindow(start24, end24)) {
      patch['locked'] = false;
      patch['lockReason'] = null;
      patch['lockedUntil'] = null;
    }
    await FirebaseFirestore.instance.collection('devices').doc(widget.deviceId).update(patch);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(patch.containsKey('locked') ? 'Schedule deleted & device unlocked.' : 'Schedule deleted.'),
      backgroundColor: const Color(0xFFEF4444),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final bg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor = widget.isDark ? Colors.white54 : const Color(0xFF64748B);
    final cardBg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('devices').doc(widget.deviceId).snapshots(),
      builder: (context, snap) {
        final liveData = snap.data?.data() as Map<String, dynamic>? ?? widget.deviceData;
        final existing = (liveData['lockSchedules'] as List<dynamic>? ?? [])
            .map((s) => Map<String, dynamic>.from(s as Map)).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(15, 0, 15, 15),
      height: h * 0.78,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.hardEdge,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
          decoration: const BoxDecoration(color: Color(0xFF6366F1)),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 24)),
            const SizedBox(width: 14),
            Text('Schedule Lock', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context),
              child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20))),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('New Lock Schedule', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: textColor)),
            const SizedBox(height: 4),
            Text('Set a time range when the device will be locked automatically.', style: GoogleFonts.outfit(fontSize: 12, color: subColor)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => _pickTime(true),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Lock From', style: GoogleFonts.outfit(fontSize: 11, color: subColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.access_time_rounded, color: Color(0xFF6366F1), size: 16),
                      const SizedBox(width: 6),
                      Flexible(child: Text(_fmtTime(_startTime), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: textColor), overflow: TextOverflow.ellipsis)),
                    ]),
                  ]),
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                onTap: () => _pickTime(false),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Unlock At', style: GoogleFonts.outfit(fontSize: 11, color: subColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.access_time_filled_rounded, color: Color(0xFF22C55E), size: 16),
                      const SizedBox(width: 6),
                      Flexible(child: Text(_fmtTime(_endTime), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: textColor), overflow: TextOverflow.ellipsis)),
                    ]),
                  ]),
                ),
              )),
            ]),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _saving ? null : () => _addSchedule(existing),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: _saving ? const Color(0xFF6366F1).withOpacity(0.6) : const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text('Add Lock Schedule', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                    ]),
                ),
              ),
            ),
            if (existing.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(children: [
                Text('Active Schedules', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: textColor)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: Text('${existing.length}', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF6366F1))),
                ),
              ]),
              const SizedBox(height: 10),
              ...existing.asMap().entries.map((e) {
                final s = e.value;
                final start24 = s['start'] as String? ?? '';
                final end24   = s['end']   as String? ?? '';
                final activeNow = _isNowInWindow(start24, end24);
                final borderCol = activeNow
                    ? const Color(0xFFEF4444).withOpacity(0.6)
                    : const Color(0xFF6366F1).withOpacity(0.25);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: activeNow ? const Color(0xFFEF4444).withOpacity(0.06) : cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderCol),
                  ),
                  child: Row(children: [
                    Icon(activeNow ? Icons.lock_rounded : Icons.lock_clock_rounded,
                        color: activeNow ? const Color(0xFFEF4444) : const Color(0xFF6366F1), size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_to12h(start24)} → ${_to12h(end24)}',
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                      const SizedBox(height: 3),
                      if (activeNow)
                        Row(children: [
                          Container(width: 7, height: 7,
                              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text('Locking right now', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                        ])
                      else
                        Text('Device locked during this period',
                            style: GoogleFonts.outfit(fontSize: 11, color: subColor)),
                    ])),
                    GestureDetector(
                      onTap: () => _deleteSchedule(existing, e.key),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                      ),
                    ),
                  ]),
                );
              }),
            ],
          ]),
        )),
      ]),
    );
    },  // closes StreamBuilder builder
  );   // closes StreamBuilder
  }
}

// ─── Schedules ───────────────────────────────────────────────────────────────
class _MobileSchedulesView extends StatelessWidget {
  final bool isDark;
  const _MobileSchedulesView({required this.isDark});
  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        final List<Map<String, dynamic>> rules = [];
        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          String to12hLocal(String t) { if (t.toUpperCase().contains('AM') || t.toUpperCase().contains('PM')) return t; final parts = t.split(':'); if (parts.length < 2) return t; int h = int.tryParse(parts[0]) ?? 0; final m = int.tryParse(parts[1]) ?? 0; final p = h < 12 ? 'AM' : 'PM'; h = h % 12; if (h == 0) h = 12; return '$h:${m.toString().padLeft(2,'0')} $p'; }
          for (var s in (data['lockSchedules'] as List<dynamic>? ?? [])) {
            final sm = s as Map;
            rules.add({
              'deviceId': doc.id, 'type': 'Device Lock', 'target': 'Full Device',
              'time': '${to12hLocal(sm['start'] ?? '')} - ${to12hLocal(sm['end'] ?? '')}',
              'rawStart': sm['start'] ?? '', 'rawEnd': sm['end'] ?? '',
              'isLock': true,
            });
          }
          (data['appSchedules'] as Map<String, dynamic>? ?? {}).forEach((pkg, sched) {
            final s = sched as Map<String, dynamic>;
            final alwaysBlocked = s['alwaysBlocked'] == true;
            final rawStart = s['start'] as String? ?? '';
            final rawEnd = s['end'] as String? ?? '';
            rules.add({
              'deviceId': doc.id, 'type': 'App Restriction',
              'target': pkg.split('.').last,
              'pkg': pkg,
              'rawStart': rawStart,
              'rawEnd': rawEnd,
              'alwaysBlocked': alwaysBlocked,
              'time': alwaysBlocked ? 'Always Blocked' : '${to12hLocal(rawStart)} - ${to12hLocal(rawEnd)}',
              'isLock': false,
            });
          });
        }
        return Container(
          color: bg,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Schedules', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF6366F1)),
                    const SizedBox(width: 4),
                    Text('Back', style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF6366F1), fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              if (rules.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text('No schedules set yet.', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: isDark ? Colors.white38 : const Color(0xFF94A3B8)))))
              else
                ...rules.map((r) => _MobileScheduleCard(rule: r, isDark: isDark)),
            ]),
          ),
        );
      },
    );
  }
}

class _MobileScheduleCard extends StatelessWidget {
  final Map<String, dynamic> rule; final bool isDark;
  const _MobileScheduleCard({required this.rule, required this.isDark});

  Future<void> _handleDelete(BuildContext context) async {
    final deviceId = rule['deviceId'] as String? ?? '';
    if (deviceId.isEmpty) return;
    final isLock = rule['isLock'] == true;
    final snap = await FirebaseFirestore.instance.collection('devices').doc(deviceId).get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    if (isLock) {
      final rawStart = rule['rawStart'] as String? ?? '';
      final rawEnd   = rule['rawEnd']   as String? ?? '';
      final list = List<Map<String, dynamic>>.from(
        (data['lockSchedules'] ?? []).map((s) => Map<String, dynamic>.from(s as Map))
      );
      list.removeWhere((s) => s['start'] == rawStart && s['end'] == rawEnd);
      await FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'lockSchedules': list});
    } else {
      final pkg = rule['pkg'] as String? ?? '';
      if (pkg.isEmpty) return;
      final schedules = Map<String, dynamic>.from(data['appSchedules'] ?? {});
      schedules.remove(pkg);
      await FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'appSchedules': schedules});
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Schedule deleted.'), backgroundColor: Color(0xFFEF4444),
      ));
    }
  }

  Future<void> _handleEdit(BuildContext context) async {
    final deviceId = rule['deviceId'] as String? ?? '';
    if (deviceId.isEmpty) return;
    final isLock = rule['isLock'] == true;

    if (isLock) {
      // Device Lock: open ScheduleLockSheet to manage lock schedules
      final data = await FirebaseFirestore.instance.collection('devices').doc(deviceId).get();
      if (context.mounted) {
        showModalBottomSheet(
          context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
          builder: (_) => _ScheduleLockSheet(deviceId: deviceId, deviceData: data.data() ?? {}, isDark: isDark),
        );
      }
    } else {
      // App Restriction: show inline edit dialog
      final pkg = rule['pkg'] as String? ?? '';
      if (pkg.isEmpty) return;
      final target = rule['target'] as String? ?? pkg;
      bool alwaysBlocked = rule['alwaysBlocked'] == true;
      TimeOfDay startTime = const TimeOfDay(hour: 22, minute: 0);
      TimeOfDay endTime   = const TimeOfDay(hour: 6,  minute: 0);

      String fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
      String fmtDisplay(TimeOfDay t) {
        final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
        final p = t.period == DayPeriod.am ? 'AM' : 'PM';
        return '$h:${t.minute.toString().padLeft(2,'0')} $p';
      }

      // Try to parse existing raw start/end
      final rawStart = rule['rawStart'] as String? ?? '';
      final rawEnd   = rule['rawEnd']   as String? ?? '';
      final sp = rawStart.split(':');
      final ep = rawEnd.split(':');
      if (sp.length >= 2) startTime = TimeOfDay(hour: int.tryParse(sp[0]) ?? 22, minute: int.tryParse(sp[1]) ?? 0);
      if (ep.length >= 2) endTime   = TimeOfDay(hour: int.tryParse(ep[0]) ?? 6,  minute: int.tryParse(ep[1]) ?? 0);

      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F1A35) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Edit App Rule', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF1E293B))),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(target.toUpperCase(), style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text('Always Restricted', style: GoogleFonts.outfit(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text('Restrict 24/7', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 11)),
                value: alwaysBlocked,
                activeColor: const Color(0xFFEF4444),
                onChanged: (v) => setS(() => alwaysBlocked = v),
              ),
              if (!alwaysBlocked) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final s = await showTimePicker(context: ctx, initialTime: startTime, helpText: 'Lock Start Time');
                    if (s == null) return;
                    final e = await showTimePicker(context: ctx, initialTime: endTime, helpText: 'Unlock Time');
                    if (e == null) return;
                    setS(() { startTime = s; endTime = e; });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.access_time_rounded, color: Color(0xFF6366F1), size: 18),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Time Window', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8))),
                        Text('${fmtDisplay(startTime)} → ${fmtDisplay(endTime)}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1E293B))),
                      ])),
                      const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF94A3B8)),
                    ]),
                  ),
                ),
              ],
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final doc = await FirebaseFirestore.instance.collection('devices').doc(deviceId).get();
                  if (!doc.exists) return;
                  final data = doc.data() as Map<String, dynamic>;
                  final schedules = Map<String, dynamic>.from(data['appSchedules'] ?? {});
                  schedules[pkg] = {'start': fmt(startTime), 'end': fmt(endTime), 'alwaysBlocked': alwaysBlocked};
                  await FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'appSchedules': schedules});
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('App rule updated.'), backgroundColor: Color(0xFF10B981)));
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLock = rule['isLock'] == true;
    final color = isLock ? const Color(0xFFEF4444) : const Color(0xFF6366F1);
    final bg = isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.35), width: 1.5)),
      child: Row(children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(isLock ? Icons.smartphone_rounded : Icons.apps_rounded, color: color, size: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(rule['type'] ?? '', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: color))),
            const SizedBox(width: 6),
            Expanded(child: Text(rule['deviceId'] ?? '', style: GoogleFonts.outfit(fontSize: 10, color: subColor), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Text(rule['target'] ?? '', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: textColor)),
          const SizedBox(height: 4),
          Row(children: [Icon(Icons.schedule_rounded, size: 13, color: subColor), const SizedBox(width: 4), Text(rule['time'] ?? '', style: GoogleFonts.outfit(fontSize: 12, color: subColor))]),
        ])),
        Column(children: [
          GestureDetector(
            onTap: () => _handleEdit(context),
            child: Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.12), shape: BoxShape.circle), child: const Icon(Icons.edit_rounded, color: Color(0xFF6366F1), size: 16)),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _handleDelete(context),
            child: Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.12), shape: BoxShape.circle), child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 16)),
          ),
        ]),
      ]),
    );
  }
}

// ─── App Controls ─────────────────────────────────────────────────────────────
class _MobileAppControlsView extends StatefulWidget {
  final bool isDark;
  final Function(_DashboardMenu)? onNavigate;
  const _MobileAppControlsView({required this.isDark, this.onNavigate});
  @override State<_MobileAppControlsView> createState() => _MobileAppControlsViewState();
}
class _MobileAppControlsViewState extends State<_MobileAppControlsView> {
  String? _selDeviceId; String _filterMode = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _to12hMobile(String t24) {
    final p = t24.split(':');
    if (p.length < 2) return t24;
    int h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    final period = h < 12 ? 'AM' : 'PM';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')}$period';
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    final cardBg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor = widget.isDark ? Colors.white54 : const Color(0xFF64748B);
    final borderColor = const Color(0xFF6366F1).withOpacity(0.3);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snap.data!.docs;
        if (devices.isEmpty) return Center(child: Text('No devices paired.', style: GoogleFonts.outfit(color: subColor)));
        _selDeviceId ??= devices.first.id;
        final selDoc = devices.any((d) => d.id == _selDeviceId) ? devices.firstWhere((d) => d.id == _selDeviceId) : devices.first;
        final data = selDoc.data() as Map<String, dynamic>;
        final apps = data['installedApps'] as List<dynamic>? ?? [];
        final blockedApps = (data['blockedApps'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
        final hiddenApps = (data['hiddenApps'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
        final appSchedulesMap = data['appSchedules'] as Map<String, dynamic>? ?? {};
        // Helper: is a schedule entry currently active?
        bool isSchedActive(Map<String, dynamic> s) {
          if (s['alwaysBlocked'] == true) return true;
          final sp = (s['start'] as String? ?? '').split(':');
          final ep = (s['end']   as String? ?? '').split(':');
          if (sp.length < 2 || ep.length < 2) return false;
          final now = TimeOfDay.now();
          final nowMin = now.hour * 60 + now.minute;
          final sMin = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
          final eMin = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
          return sMin <= eMin ? nowMin >= sMin && nowMin < eMin : nowMin >= sMin || nowMin < eMin;
        }
        // All packages that are blocked explicitly OR have any schedule (active or not)
        final effectivelyBlocked = <String>{
          ...blockedApps,
          ...appSchedulesMap.keys,
        };
        // Build a lookup map from packageName -> app data for enrichment
        final installedMap = <String, Map<String, dynamic>>{};
        for (final a in apps) {
          final m = a as Map<String, dynamic>;
          final p = (m['packageName'] ?? '').toString();
          if (p.isNotEmpty) installedMap[p] = m;
        }
        List<Map<String, dynamic>> filtered;
        if (_filterMode == 'blocked') {
          // Show all effectively-blocked packages; enrich with installedApps data where available
          filtered = effectivelyBlocked.map<Map<String, dynamic>>((pkg) =>
            installedMap[pkg] ?? {'packageName': pkg, 'appName': '', 'name': '', 'label': ''}
          ).where((app) {
            final pkg = (app['packageName'] ?? '').toString();
            final name = (app['appName'] ?? app['name'] ?? app['label'] ?? pkg).toString().toLowerCase();
            final effectiveName = name.isNotEmpty ? name : pkg.toLowerCase();
            if (_searchQuery.isNotEmpty && !effectiveName.contains(_searchQuery) && !pkg.toLowerCase().contains(_searchQuery)) return false;
            return true;
          }).toList();
        } else if (_filterMode == 'hidden') {
          // Show all hidden packages; enrich with installedApps data where available
          filtered = hiddenApps.map<Map<String, dynamic>>((pkg) =>
            installedMap[pkg] ?? {'packageName': pkg, 'appName': '', 'name': '', 'label': ''}
          ).where((app) {
            final pkg = (app['packageName'] ?? '').toString();
            final name = (app['appName'] ?? app['name'] ?? app['label'] ?? pkg).toString().toLowerCase();
            final effectiveName = name.isNotEmpty ? name : pkg.toLowerCase();
            if (_searchQuery.isNotEmpty && !effectiveName.contains(_searchQuery) && !pkg.toLowerCase().contains(_searchQuery)) return false;
            return true;
          }).toList();
        } else {
          filtered = apps.where((app) {
            final d = app as Map<String, dynamic>;
            final pkg = (d['packageName'] ?? '').toString();
            final name = (d['appName'] ?? d['name'] ?? d['label'] ?? pkg).toString().toLowerCase();
            if (_filterMode == 'allowed') { if (effectivelyBlocked.contains(pkg) || hiddenApps.contains(pkg)) return false; }
            if (_searchQuery.isNotEmpty && !name.contains(_searchQuery) && !pkg.toLowerCase().contains(_searchQuery)) return false;
            return true;
          }).cast<Map<String, dynamic>>().toList();
        }
        return Container(
          color: bg,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('App Controls', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    if (widget.onNavigate != null) {
                      widget.onNavigate!(_DashboardMenu.dashboard);
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  },
                  child: Row(children: [
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF6366F1)),
                    const SizedBox(width: 4),
                    Text('Back', style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF6366F1), fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _MobileDropBox(value: _selDeviceId!, items: devices.map((d) => d.id).toList(), icon: Icons.phone_android_rounded, isDark: widget.isDark, onChanged: (v) => setState(() => _selDeviceId = v))),
                const SizedBox(width: 10),
                Expanded(child: _MobileDropBox(value: _filterMode, items: const ['all', 'blocked', 'hidden', 'allowed'], icon: Icons.apps_rounded, isDark: widget.isDark, onChanged: (v) => setState(() => _filterMode = v))),
              ]),
              const SizedBox(height: 10),
              // Search field
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.outfit(fontSize: 13, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search apps...', hintStyle: GoogleFonts.outfit(fontSize: 13, color: subColor),
                    border: InputBorder.none, icon: Icon(Icons.search_rounded, color: subColor, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: Icon(Icons.clear_rounded, size: 16, color: subColor), onPressed: () => _searchCtrl.clear()) : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Apps (${filtered.length})', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: subColor)),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text(
                  _filterMode != 'all' ? 'No ${_filterMode} apps found.' : 'No apps found.',
                  style: GoogleFonts.outfit(color: subColor),
                )))
              else
                ListView.builder(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final app = filtered[i] as Map<String, dynamic>;
                    final name = (app['appName'] ?? app['name'] ?? app['label'] ?? '').toString();
                    final pkg = (app['packageName'] ?? '').toString();
                    // Derive friendly package name as fallback
                    final pkgParts = pkg.split('.');
                    final friendlyPkg = pkgParts.isNotEmpty ? pkgParts.last.split('_').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ') : pkg;
                    final displayName = name.isNotEmpty ? name : friendlyPkg;
                    final isBlocked = blockedApps.contains(pkg);
                    final isHidden = hiddenApps.contains(pkg);
                    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
                    final circleColors = [const Color(0xFFFDE68A), const Color(0xFFBFDBFE), const Color(0xFFFCE7F3), const Color(0xFFD1FAE5), const Color(0xFFE0E7FF)];
                    final tColors = [const Color(0xFFD97706), const Color(0xFF1D4ED8), const Color(0xFFBE185D), const Color(0xFF065F46), const Color(0xFF3730A3)];
                    final ci = displayName.isNotEmpty ? displayName.codeUnitAt(0) % circleColors.length : 0;
                    final borderCol = isBlocked ? const Color(0xFFEF4444).withOpacity(0.4) : isHidden ? const Color(0xFFFBBF24).withOpacity(0.4) : borderColor;
                    // Check for block schedule on this app (stored in appSchedules map)
                    final appScheduleMapAll = data['appSchedules'] as Map<String, dynamic>? ?? {};
                    final appSchedEntry = appScheduleMapAll[pkg] as Map<String, dynamic>?;
                    final hasSchedule = appSchedEntry != null;
                    bool scheduleActiveNow = false;
                    if (appSchedEntry != null) {
                      final sp = (appSchedEntry['start'] as String? ?? '').split(':');
                      final ep = (appSchedEntry['end']   as String? ?? '').split(':');
                      if (sp.length >= 2 && ep.length >= 2) {
                        final now = TimeOfDay.now();
                        final nowMin = now.hour * 60 + now.minute;
                        final startMin = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
                        final endMin   = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
                        scheduleActiveNow = startMin <= endMin
                            ? nowMin >= startMin && nowMin < endMin
                            : nowMin >= startMin || nowMin < endMin;
                      }
                    }
                    final effectiveBorderCol = scheduleActiveNow
                        ? const Color(0xFFEF4444).withOpacity(0.6)
                        : borderCol;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: effectiveBorderCol)),
                      child: Row(children: [
                        Container(width: 42, height: 42, decoration: BoxDecoration(color: circleColors[ci], shape: BoxShape.circle), child: Center(child: Text(initial, style: GoogleFonts.outfit(color: tColors[ci], fontSize: 18, fontWeight: FontWeight.w900)))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(displayName, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: textColor), softWrap: true),
                          const SizedBox(height: 2),
                          Row(children: [
                            if (isBlocked) _AppStatusBadge('Blocked', const Color(0xFFEF4444))
                            else if (isHidden) _AppStatusBadge('Hidden', const Color(0xFFFBBF24))
                            else _AppStatusBadge('Allowed', const Color(0xFF22C55E)),
                            if (hasSchedule) ...[
                              const SizedBox(width: 6),
                              _AppStatusBadge(
                                scheduleActiveNow ? '⏱ Blocking Now' : '⏱ Scheduled',
                                scheduleActiveNow ? const Color(0xFFEF4444) : const Color(0xFF6366F1),
                              ),
                              if (appSchedEntry != null && appSchedEntry['alwaysBlocked'] != true) ...[
                                const SizedBox(width: 4),
                                _AppStatusBadge(
                                  '${_to12hMobile(appSchedEntry['start'] ?? '')}–${_to12hMobile(appSchedEntry['end'] ?? '')}',
                                  const Color(0xFF94A3B8),
                                ),
                              ],
                            ],
                          ]),
                        ])),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 18),
                          color: cardBg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.zero,
                          onSelected: (action) async {
                            final ref = FirebaseFirestore.instance.collection('devices').doc(selDoc.id);
                            if (action == 'schedule_block') {
                              showModalBottomSheet(
                                context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                                builder: (_) => _AppBlockScheduleSheet(
                                  deviceId: selDoc.id, pkg: pkg, appName: displayName, isDark: widget.isDark,
                                ),
                              );
                              return;
                            }
                            final List<dynamic> blocked = List.from(data['blockedApps'] ?? []);
                            final List<dynamic> hidden  = List.from(data['hiddenApps']  ?? []);
                            if (action == 'block_now') { blocked.add(pkg); hidden.remove(pkg); }
                            else if (action == 'hide') { hidden.add(pkg); blocked.remove(pkg); }
                            else if (action == 'allow') { blocked.remove(pkg); hidden.remove(pkg); }
                            await ref.update({'blockedApps': blocked, 'hiddenApps': hidden});
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'allow', child: Row(children: [const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 16), const SizedBox(width: 8), Text('Allow', style: GoogleFonts.outfit(fontSize: 13, color: textColor))])),
                            PopupMenuItem(value: 'block_now', child: Row(children: [const Icon(Icons.block_rounded, color: Color(0xFFEF4444), size: 16), const SizedBox(width: 8), Text('Block instantly', style: GoogleFonts.outfit(fontSize: 13, color: textColor))])),
                            PopupMenuItem(value: 'hide', child: Row(children: [const Icon(Icons.visibility_off_rounded, color: Color(0xFFFBBF24), size: 16), const SizedBox(width: 8), Text('Hide', style: GoogleFonts.outfit(fontSize: 13, color: textColor))])),
                            const PopupMenuDivider(),
                            PopupMenuItem(value: 'schedule_block', child: Row(children: [const Icon(Icons.schedule_rounded, color: Color(0xFF6366F1), size: 16), const SizedBox(width: 8), Text('Schedule Block', style: GoogleFonts.outfit(fontSize: 13, color: textColor, fontWeight: FontWeight.w700))])),
                          ],
                        ),
                      ]),
                    );
                  },
                ),
            ]),
          ),
        );
      },
    );
  }
}

class _MobileDropBox extends StatelessWidget {
  final String value; final List<String> items; final IconData icon; final bool isDark; final Function(String) onChanged;
  const _MobileDropBox({required this.value, required this.items, required this.icon, required this.isDark, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3))),
      child: Row(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: const Color(0xFF6366F1), size: 16)),
        const SizedBox(width: 6),
        Expanded(child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first, isExpanded: true, underline: const SizedBox(),
          dropdownColor: isDark ? const Color(0xFF0F1A35) : Colors.white,
          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: textColor),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6366F1), size: 18),
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i.toUpperCase()))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        )),
      ]),
    );
  }
}

// ─── App Status Badge ─────────────────────────────────────────────────────────
class _AppStatusBadge extends StatelessWidget {
  final String label; final Color color;
  const _AppStatusBadge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );
}

// ─── App Block Schedule Sheet ─────────────────────────────────────────────────
class _AppBlockScheduleSheet extends StatefulWidget {
  final String deviceId, pkg, appName; final bool isDark;
  const _AppBlockScheduleSheet({required this.deviceId, required this.pkg, required this.appName, required this.isDark});
  @override State<_AppBlockScheduleSheet> createState() => _AppBlockScheduleSheetState();
}
class _AppBlockScheduleSheetState extends State<_AppBlockScheduleSheet> {
  TimeOfDay _startTime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _endTime   = const TimeOfDay(hour: 6,  minute: 0);
  bool _saving = false;

  String _fmt24(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmt12(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  String _to12h(String t24) {
    final p = t24.split(':'); if (p.length < 2) return t24;
    int h = int.tryParse(p[0]) ?? 0; final m = int.tryParse(p[1]) ?? 0;
    final period = h < 12 ? 'AM' : 'PM'; h = h % 12; if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')} $period';
  }

  bool _isNowInWindow(String s24, String e24) {
    final sp = s24.split(':'); final ep = e24.split(':');
    if (sp.length < 2 || ep.length < 2) return false;
    final now = TimeOfDay.now(); final nowMin = now.hour * 60 + now.minute;
    final sMin = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
    final eMin = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
    if (sMin <= eMin) return nowMin >= sMin && nowMin < eMin;
    return nowMin >= sMin || nowMin < eMin;
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(
      context: context, initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1))), child: child!),
    );
    if (t != null) setState(() { if (isStart) _startTime = t; else _endTime = t; });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final start = _fmt24(_startTime);
      final end = _fmt24(_endTime);
      final activeNow = _isNowInWindow(start, end);
      final snap = await FirebaseFirestore.instance.collection('devices').doc(widget.deviceId).get();
      final scheduleMap = Map<String, dynamic>.from(snap.data()?['appSchedules'] ?? {});
      scheduleMap[widget.pkg] = {'start': start, 'end': end, 'alwaysBlocked': false};
      final Map<String, dynamic> patch = {'appSchedules': scheduleMap};
      if (activeNow) {
        final blocked = List<dynamic>.from(snap.data()?['blockedApps'] ?? []);
        if (!blocked.contains(widget.pkg)) blocked.add(widget.pkg);
        patch['blockedApps'] = blocked;
      }
      await FirebaseFirestore.instance.collection('devices').doc(widget.deviceId).update(patch);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: Text(activeNow ? 'Schedule saved & app blocked now!' : 'Block schedule saved!'),
          backgroundColor: const Color(0xFF22C55E),
        ));
      }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _deleteSchedule() async {
    final snap = await FirebaseFirestore.instance.collection('devices').doc(widget.deviceId).get();
    final scheduleMap = Map<String, dynamic>.from(snap.data()?['appSchedules'] ?? {});
    final entry = scheduleMap[widget.pkg] as Map<String, dynamic>?;
    scheduleMap.remove(widget.pkg);
    final Map<String, dynamic> patch = {'appSchedules': scheduleMap};
    if (entry != null && _isNowInWindow(entry['start'] as String? ?? '', entry['end'] as String? ?? '')) {
      final blocked = List<dynamic>.from(snap.data()?['blockedApps'] ?? [])..remove(widget.pkg);
      patch['blockedApps'] = blocked;
    }
    await FirebaseFirestore.instance.collection('devices').doc(widget.deviceId).update(patch);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Block schedule removed.'), backgroundColor: Color(0xFFEF4444),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final bg      = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final cardBg  = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor  = widget.isDark ? Colors.white54 : const Color(0xFF64748B);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('devices').doc(widget.deviceId).snapshots(),
      builder: (context, snap) {
        final liveData  = snap.data?.data() as Map<String, dynamic>? ?? {};
        final appScheduleMap = liveData['appSchedules'] as Map<String, dynamic>? ?? {};
        final existingEntry = appScheduleMap[widget.pkg] as Map<String, dynamic>?;

        return Container(
          margin: const EdgeInsets.fromLTRB(15, 0, 15, 15),
          height: h * 0.78,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
          clipBehavior: Clip.hardEdge,
          child: Column(children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
              decoration: const BoxDecoration(color: Color(0xFF6366F1)),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 24)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Schedule Block', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text(widget.appName, style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70), overflow: TextOverflow.ellipsis),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context),
                    child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 20))),
              ]),
            ),
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New Block Schedule', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: textColor)),
                const SizedBox(height: 4),
                Text('Set a time range when this app will be automatically blocked.', style: GoogleFonts.outfit(fontSize: 12, color: subColor)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => _pickTime(true),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Block From', style: GoogleFonts.outfit(fontSize: 11, color: subColor, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.access_time_rounded, color: Color(0xFF6366F1), size: 16),
                          const SizedBox(width: 6),
                          Flexible(child: Text(_fmt12(_startTime), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: textColor), overflow: TextOverflow.ellipsis)),
                        ]),
                      ]),
                    ),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: GestureDetector(
                    onTap: () => _pickTime(false),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Unblock At', style: GoogleFonts.outfit(fontSize: 11, color: subColor, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.access_time_filled_rounded, color: Color(0xFF22C55E), size: 16),
                          const SizedBox(width: 6),
                          Flexible(child: Text(_fmt12(_endTime), style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: textColor), overflow: TextOverflow.ellipsis)),
                        ]),
                      ]),
                    ),
                  )),
                ]),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: _saving ? const Color(0xFF6366F1).withOpacity(0.6) : const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(existingEntry != null ? Icons.save_rounded : Icons.add_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(existingEntry != null ? 'Update Schedule' : 'Add Block Schedule',
                              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                        ])),
                  ),
                ),
                if (existingEntry != null) ...[
                  const SizedBox(height: 24),
                  Text('Current Schedule', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: textColor)),
                  const SizedBox(height: 10),
                  () {
                    final s24 = existingEntry['start'] as String? ?? '';
                    final e24 = existingEntry['end']   as String? ?? '';
                    final activeNow = _isNowInWindow(s24, e24);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: activeNow ? const Color(0xFFEF4444).withOpacity(0.06) : cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: activeNow ? const Color(0xFFEF4444).withOpacity(0.5) : const Color(0xFF6366F1).withOpacity(0.25)),
                      ),
                      child: Row(children: [
                        Icon(activeNow ? Icons.block_rounded : Icons.schedule_rounded,
                            color: activeNow ? const Color(0xFFEF4444) : const Color(0xFF6366F1), size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_to12h(s24)} → ${_to12h(e24)}',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                          const SizedBox(height: 3),
                          if (activeNow)
                            Row(children: [
                              Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              Text('Blocking right now', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                            ])
                          else
                            Text('App blocked during this time window', style: GoogleFonts.outfit(fontSize: 11, color: subColor)),
                        ])),
                        GestureDetector(
                          onTap: _deleteSchedule,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                          ),
                        ),
                      ]),
                    );
                  }(),
                ],
              ]),
            )),
          ]),
        );
      },
    );
  }
}

// ─── Location ─────────────────────────────────────────────────────────────────
class _MobileLocationView extends StatefulWidget {
  final bool isDark;
  final Function(_DashboardMenu)? onNavigate;
  const _MobileLocationView({required this.isDark, this.onNavigate});
  @override State<_MobileLocationView> createState() => _MobileLocationViewState();
}

class _MobileLocationViewState extends State<_MobileLocationView> with SingleTickerProviderStateMixin {
  bool _syncing = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _triggerSync() {
    setState(() => _syncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text('Live sync active — fetching latest GPS coordinates...', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        ]),
        backgroundColor: const Color(0xFF22C55E),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snap.data!.docs;
        int active = devices.where((d) => (d.data() as Map)['status'] == 'online').length;
        final List<Marker> markers = [];
        LatLng center = const LatLng(14.5995, 120.9842);
        for (var doc in devices) {
          final data = doc.data() as Map<String, dynamic>;
          final deviceName = (data['deviceName'] ?? data['model'] ?? data['name'] ?? doc.id).toString();
          final lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
          final lng = (data['lng'] as num?)?.toDouble() ?? 0.0;
          if (lat != 0.0 || lng != 0.0) {
            center = LatLng(lat, lng);
            markers.add(Marker(point: LatLng(lat, lng), width: 80, height: 70, child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF22C55E))),
                child: Text(deviceName.length > 12 ? '${deviceName.substring(0, 10)}...' : deviceName, style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)))),
              const Icon(Icons.location_on_rounded, color: Colors.red, size: 28),
            ])));
          }
        }
        return Container(
          color: bg,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tracking $active active device${active == 1 ? '' : 's'}', style: GoogleFonts.outfit(fontSize: 13, color: textColor, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  if (_syncing) Text('Syncing location data...', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF22C55E), fontWeight: FontWeight.w500)),
                ])),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _triggerSync,
                  child: AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _syncing ? const Color(0xFF22C55E) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF22C55E), width: _syncing ? 0 : 1),
                        boxShadow: _syncing ? [BoxShadow(color: const Color(0xFF22C55E).withOpacity(_pulseAnim.value * 0.5), blurRadius: 12, spreadRadius: 2)] : [],
                      ),
                      child: Row(children: [
                        _syncing
                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.my_location_rounded, color: Color(0xFF22C55E), size: 16),
                        const SizedBox(width: 6),
                        Text('Live Sync', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: _syncing ? Colors.white : const Color(0xFF22C55E))),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (widget.onNavigate != null) {
                      widget.onNavigate!(_DashboardMenu.dashboard);
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3))),
                    child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF6366F1), size: 16),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Expanded(child: Stack(children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF22C55E).withOpacity(_syncing ? 1.0 : 0.5), width: _syncing ? 3 : 2),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: FlutterMap(
                    options: MapOptions(initialCenter: center, initialZoom: 13),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.parentalcontrol.applocker'),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                ),
                if (_syncing)
                  Positioned(
                    top: 12, left: 0, right: 0,
                    child: Center(child: AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, __) => Opacity(
                        opacity: _pulseAnim.value,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.wifi_tethering_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text('Fetching live GPS data...', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                          ]),
                        ),
                      ),
                    )),
                  ),
              ])),
            ]),
          ),
        );
      },
    );
  }
}

// ─── Monitoring ───────────────────────────────────────────────────────────────
class _MobileMonitoringView extends StatefulWidget {
  final bool isDark;
  const _MobileMonitoringView({required this.isDark});
  @override State<_MobileMonitoringView> createState() => _MobileMonitoringViewState();
}
class _MobileMonitoringViewState extends State<_MobileMonitoringView> {
  String _category = 'App Opened';
  String? _selDeviceId;
  static const _cats = ['App Opened', 'Web Activity', 'Message Activity', 'Calls & Messages'];

  Future<void> _clearHistory(BuildContext context, String deviceId) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Clear History', style: GoogleFonts.outfit(fontWeight: FontWeight.w900)),
        content: Text('Delete all $_category records for this device? This cannot be undone.', style: GoogleFonts.outfit()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.outfit())),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Clear All', style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final types = _category == 'Calls & Messages' ? [_activityType, 'sms'] : [_activityType];
    for (final type in types) {
      final snap = await FirebaseFirestore.instance.collection('devices').doc(deviceId).collection('activity').where('type', isEqualTo: type).get();
      for (final doc in snap.docs) await doc.reference.delete();
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History cleared!'), backgroundColor: Color(0xFF22C55E)));
  }

  String get _activityType {
    switch (_category) {
      case 'Web Activity': return 'url';
      case 'Message Activity': return 'message';
      case 'Calls & Messages': return 'call';
      default: return 'app_usage';
    }
  }
  String get _listLabel { switch (_category) { case 'Web Activity': return 'Websites'; case 'Message Activity': return 'Messages'; case 'Calls & Messages': return 'Calls & Messages'; default: return 'Apps'; } }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    final cardBg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor = widget.isDark ? Colors.white54 : const Color(0xFF64748B);
    final border = const Color(0xFF6366F1).withOpacity(0.3);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, devSnap) {
        if (!devSnap.hasData) return const Center(child: CircularProgressIndicator());
        final devices = devSnap.data!.docs;
        if (devices.isEmpty) return Center(child: Text('No devices.', style: GoogleFonts.outfit(color: subColor)));
        _selDeviceId ??= devices.first.id;
        final deviceId = devices.any((d) => d.id == _selDeviceId) ? _selDeviceId! : devices.first.id;

        return Container(
          color: bg,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
                  child: Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.touch_app_rounded, color: Color(0xFF6366F1), size: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: DropdownButton<String>(
                      value: _category, isExpanded: true, underline: const SizedBox(),
                      dropdownColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: textColor),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6366F1)),
                      items: _cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) { if (v != null) setState(() => _category = v); },
                    )),
                  ]),
                ),
                const SizedBox(height: 8),
                if (devices.length > 1) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
                  child: Row(children: [
                    const Icon(Icons.smartphone_rounded, color: Color(0xFF22C55E), size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: DropdownButton<String>(
                      value: devices.any((d) => d.id == _selDeviceId) ? _selDeviceId : devices.first.id,
                      isExpanded: true, underline: const SizedBox(),
                      dropdownColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF22C55E), size: 18),
                      items: devices.map((d) { final n = ((d.data() as Map)['model'] ?? (d.data() as Map)['name'] ?? d.id).toString(); return DropdownMenuItem(value: d.id, child: Text(n, overflow: TextOverflow.ellipsis)); }).toList(),
                      onChanged: (v) => setState(() => _selDeviceId = v),
                    )),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Expanded(child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('devices').doc(deviceId).collection('activity')
                  .where('type', isEqualTo: _activityType).orderBy('timestamp', descending: true).limit(30).snapshots(),
              builder: (context, snap) {
                final mainDocs = snap.data?.docs ?? [];
                return StreamBuilder<QuerySnapshot>(
                  stream: _category == 'Calls & Messages'
                      ? FirebaseFirestore.instance.collection('devices').doc(deviceId).collection('activity').where('type', isEqualTo: 'sms').orderBy('timestamp', descending: true).limit(30).snapshots()
                      : const Stream.empty(),
                  builder: (context, smsSnap) {
                    final allDocs = [...mainDocs, ...?smsSnap.data?.docs]..sort((a, b) {
                      final at = (a.data() as Map)['timestamp'] as Timestamp?;
                      final bt = (b.data() as Map)['timestamp'] as Timestamp?;
                      if (at == null || bt == null) return 0;
                      return bt.compareTo(at);
                    });
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(_listLabel, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _clearHistory(context, deviceId),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3))),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 15),
                                const SizedBox(width: 4),
                                Text('Clear', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        if (allDocs.isEmpty)
                          Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No activity recorded yet.', style: GoogleFonts.outfit(color: subColor))))
                        else
                          ...allDocs.where((doc) {
                            final d = doc.data() as Map<String, dynamic>;
                            // Exclude chathead/bubble notifications from Message Activity
                            if (_category == 'Message Activity') {
                              final source = (d['source'] ?? d['packageName'] ?? d['pkg'] ?? '').toString().toLowerCase();
                              final notifTitle = (d['title'] ?? '').toString().toLowerCase();
                              if (source.contains('chathead') || source.contains('bubble') ||
                                  notifTitle.contains('chathead') || notifTitle.contains('bubble')) return false;
                              // Exclude entries with no real sender info
                              final sender = (d['sender'] ?? d['contact'] ?? d['from'] ?? '').toString().trim();
                              final body = (d['content'] ?? d['body'] ?? d['message'] ?? '').toString().trim();
                              if (sender.isEmpty && body.isEmpty) return false;
                            }
                            return true;
                          }).map((doc) => _buildActivityCard(doc, cardBg, textColor, subColor, border, context)),
                      ]),
                    );
                  },
                );
              },
            )),
          ]),
        );
      },
    );
  }

  Widget _buildActivityCard(QueryDocumentSnapshot doc, Color cardBg, Color textColor, Color subColor, Color border, BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final dateStr = ts != null ? DateFormat('h:mm a MMM d').format(ts) : '';
    final type = data['type'] as String? ?? '';
    final circleColors = [const Color(0xFFFDE68A), const Color(0xFFBFDBFE), const Color(0xFFFCE7F3), const Color(0xFFD1FAE5)];
    final tColors = [const Color(0xFFD97706), const Color(0xFF1D4ED8), const Color(0xFFBE185D), const Color(0xFF065F46)];

    Widget leading; String title, subtitle = ''; Widget? trailing; String? badge; String? trailing2;

    switch (_category) {
      case 'App Opened': {
        final app = (data['appName'] ?? data['app'] ?? '').toString();
        final dMin = (((data['duration'] as int?) ?? 0) / 60000).round();
        final initial = app.isNotEmpty ? app[0].toUpperCase() : '?';
        final ci = app.isNotEmpty ? app.codeUnitAt(0) % circleColors.length : 0;
        leading = Container(width: 48, height: 48, decoration: BoxDecoration(color: circleColors[ci], shape: BoxShape.circle), child: Center(child: Text(initial, style: GoogleFonts.outfit(color: tColors[ci], fontSize: 20, fontWeight: FontWeight.w900))));
        title = app.isEmpty ? 'Unknown' : app; subtitle = dateStr;
        trailing = Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: circleColors[ci], borderRadius: BorderRadius.circular(20)), child: Text('${dMin}m', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: tColors[ci])));
        break;
      }
      case 'Web Activity': {
        final url = (data['content'] ?? data['url'] ?? data['domain'] ?? '').toString();
        final dMin = (((data['duration'] as num?) ?? 0) / 60000).round();
        leading = Container(width: 48, height: 48, decoration: const BoxDecoration(color: Color(0xFFD1FAE5), shape: BoxShape.circle), child: const Icon(Icons.language_rounded, color: Color(0xFF059669), size: 24));
        title = url.isEmpty ? 'Unknown site' : url; subtitle = 'Chrome · $dateStr';
        trailing = Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF1D4ED8), borderRadius: BorderRadius.circular(20)), child: Text('${dMin}m', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)));
        break;
      }
      case 'Message Activity': {
        final contact = (data['sender'] ?? data['title'] ?? data['contact'] ?? data['from'] ?? 'Unknown').toString();
        final body = (data['content'] ?? data['body'] ?? data['message'] ?? '').toString();
        final isIn = (data['direction'] ?? 'incoming') == 'incoming';
        leading = Container(width: 48, height: 48, decoration: const BoxDecoration(color: Color(0xFFD1FAE5), shape: BoxShape.circle), child: Icon(isIn ? Icons.south_west_rounded : Icons.north_east_rounded, color: const Color(0xFF1D4ED8), size: 24));
        title = contact.isEmpty ? (isIn ? 'Incoming' : 'Outgoing') : contact; subtitle = body; trailing2 = dateStr;
        break;
      }
      default: {
        final contact = (data['sender'] ?? data['title'] ?? data['contact'] ?? data['from'] ?? 'Unknown').toString();
        final body = (data['content'] ?? data['body'] ?? data['number'] ?? '').toString();
        final isIn = (data['direction'] ?? 'incoming') == 'incoming';
        leading = Container(width: 48, height: 48, decoration: const BoxDecoration(color: Color(0xFFD1FAE5), shape: BoxShape.circle), child: Icon(isIn ? Icons.south_west_rounded : Icons.north_east_rounded, color: const Color(0xFF1D4ED8), size: 24));
        title = contact.isEmpty ? (isIn ? 'Incoming' : 'Outgoing') : contact; subtitle = body.isEmpty ? 'No content' : body;
        badge = type == 'sms' ? 'SMS' : 'Call'; trailing2 = dateStr;
        break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        leading,
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (badge != null) ...[const SizedBox(width: 6), Text(badge, style: GoogleFonts.outfit(fontSize: 11, color: subColor))],
          ]),
          if (subtitle.isNotEmpty) ...[const SizedBox(height: 3), Text(subtitle, style: GoogleFonts.outfit(fontSize: 12, color: subColor), maxLines: 2)],
          if (trailing2 != null) ...[const SizedBox(height: 4), Align(alignment: Alignment.bottomRight, child: Text(trailing2, style: GoogleFonts.outfit(fontSize: 10, color: subColor)))],
        ])),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ]),
    );
  }
}

// ─── Reports ──────────────────────────────────────────────────────────────────
class _MobileReportsView extends StatelessWidget {
  final bool isDark;
  const _MobileReportsView({required this.isDark});
  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final border = const Color(0xFF6366F1).withOpacity(0.3);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snap.data!.docs;
        double screenTime = 0; int blocked = 0, active = 0;
        final List<Map<String, dynamic>> events = [];
        for (var doc in devices) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['status'] == 'online') active++;
          blocked += (data['blockedApps'] as List<dynamic>? ?? []).length;
          (data['usageStats'] as Map<dynamic, dynamic>? ?? {}).forEach((k, v) { if (v is num) screenTime += v / (1000 * 60 * 60); });
          if (data['status'] == 'online') events.add({'title': 'Device is online', 'device': doc.id, 'icon': Icons.cell_tower_rounded, 'color': const Color(0xFF22C55E)});
          if ((data['battery'] ?? 100) < 20) events.add({'title': 'Battery critical low', 'device': doc.id, 'icon': Icons.battery_alert_rounded, 'color': const Color(0xFFEF4444)});
          if (data['locked'] == true) events.add({'title': 'Manual lock active', 'device': doc.id, 'icon': Icons.lock_rounded, 'color': const Color(0xFF6366F1)});
        }
        return Container(
          color: bg,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _MiniStatCard(label: 'Total Screen Time', value: '${screenTime.toStringAsFixed(1)}h', liveColor: const Color(0xFF22C55E), isDark: isDark)),
                const SizedBox(width: 8),
                Expanded(child: _MiniStatCard(label: 'Block Threats', value: '$blocked', liveColor: const Color(0xFFFBBF24), isDark: isDark)),
                const SizedBox(width: 8),
                Expanded(child: _MiniStatCard(label: 'Active Devices', value: '$active', liveColor: const Color(0xFFA78BFA), isDark: isDark)),
              ]),
              const SizedBox(height: 20),
              Text('Real-time Status Alert', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
              const SizedBox(height: 10),
              if (events.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('No alerts.', style: GoogleFonts.outfit(color: isDark ? Colors.white38 : const Color(0xFF94A3B8)))))
              else
                ...events.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
                  child: Row(children: [
                    Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFD1FAE5), shape: BoxShape.circle), child: Icon(e['icon'] as IconData, color: e['color'] as Color, size: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(e['title'] as String, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: textColor))),
                    Text('${(e['device'] as String).length > 8 ? (e['device'] as String).substring(0, 8) : e['device']} - Recent', style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF94A3B8))),
                  ]),
                )),
            ]),
          ),
        );
      },
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label; final String value; final Color liveColor; final bool isDark;
  const _MiniStatCard({required this.label, required this.value, required this.liveColor, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600), maxLines: 2),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: textColor)),
        const SizedBox(height: 6),
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: liveColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
          child: Text('LIVE', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w900, color: liveColor))),
      ]),
    );
  }
}

// ─── Subscriptions ────────────────────────────────────────────────────────────
class _MobileSubscriptionView extends StatefulWidget {
  final bool isDark; final String userRole;
  const _MobileSubscriptionView({required this.isDark, required this.userRole});
  @override State<_MobileSubscriptionView> createState() => _MobileSubscriptionViewState();
}
class _MobileSubscriptionViewState extends State<_MobileSubscriptionView> {
  Map<String, dynamic>? _selectedPlan;
  String? _selectedPlanId;

  static const _planColors = {'basic': Color(0xFFA78BFA), 'starter': Color(0xFF22C55E), 'pro': Color(0xFF6366F1), 'lifetime': Color(0xFFFBBF24)};
  static const _planIcons = {'basic': Icons.monetization_on_outlined, 'starter': Icons.workspace_premium_rounded, 'pro': Icons.stars_rounded, 'lifetime': Icons.all_inclusive_rounded};

  Future<void> _upgradePlan(BuildContext context, String planId, String planName) async {
    final isDark = widget.isDark;
    final cardColor = isDark ? const Color(0xFF18181B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    String? selectedMethod;
    String? proofUrl;

    final pmSnap = await FirebaseFirestore.instance.collection('payment_methods').get();
    final paymentMethods = pmSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    if (paymentMethods.isEmpty) {
      paymentMethods.addAll([
        {'id': 'gcash', 'name': 'GCash', 'icon': '📱', 'qrUrl': '', 'accountName': 'AppLocker PH', 'accountNumber': '09XX-XXX-XXXX'},
        {'id': 'maya', 'name': 'Maya', 'icon': '💳', 'qrUrl': '', 'accountName': 'AppLocker PH', 'accountNumber': '09XX-XXX-XXXX'},
        {'id': 'bank', 'name': 'Bank Transfer', 'icon': '🏦', 'qrUrl': '', 'accountName': 'AppLocker PH', 'accountNumber': '0000-0000-0000'},
      ]);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setS) => AlertDialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          title: Row(children: [
            const Icon(Icons.payment_rounded, color: Color(0xFF6366F1)),
            const SizedBox(width: 10),
            Expanded(child: Text('Upgrade to $planName', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor, fontSize: 18))),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SELECT PAYMENT METHOD', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  ...paymentMethods.map((pm) {
                    final isSelected = selectedMethod == pm['id'];
                    return GestureDetector(
                      onTap: () => setS(() => selectedMethod = pm['id'] as String),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF6366F1).withOpacity(0.1) : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey.withOpacity(0.05)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF64748B).withOpacity(0.4), width: isSelected ? 1.5 : 0.5),
                        ),
                        child: Row(children: [
                          Text(pm['icon'] as String? ?? '💰', style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(pm['name'] as String? ?? '', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: textColor)),
                            if ((pm['accountName'] as String? ?? '').isNotEmpty)
                              Text('${pm['accountName']} · ${pm['accountNumber']}', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8))),
                          ])),
                          if (isSelected) const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1), size: 20),
                        ]),
                      ),
                    );
                  }).toList(),
                  if (selectedMethod != null) ...[
                    const SizedBox(height: 16),
                    Divider(color: const Color(0xFF64748B).withOpacity(0.3)),
                    const SizedBox(height: 12),
                    Builder(builder: (_) {
                      final pm = paymentMethods.firstWhere((p) => p['id'] == selectedMethod, orElse: () => {});
                      final qrUrl = pm['qrUrl'] as String? ?? '';
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (qrUrl.isNotEmpty) ...[
                          Text('SCAN QR CODE', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 1.2)),
                          const SizedBox(height: 8),
                          Center(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(qrUrl, height: 180, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
                          const SizedBox(height: 12),
                        ],
                        Text('PROOF OF PAYMENT', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text('After paying, paste your screenshot URL or reference number below.', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8))),
                        const SizedBox(height: 8),
                        TextField(
                          onChanged: (v) => setS(() => proofUrl = v.trim()),
                          style: GoogleFonts.outfit(fontSize: 12, color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Reference # or image URL of receipt…',
                            hintStyle: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.receipt_long_rounded, color: Color(0xFF6366F1), size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            filled: true, fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.4))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.25))),
                          ),
                        ),
                      ]);
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
            ElevatedButton(
              onPressed: selectedMethod == null ? null : () => Navigator.pop(dlgCtx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text('Submit for Approval', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedMethod == null) return;

    try {
      await FirebaseFirestore.instance.collection('transactions').add({
        'uid': uid,
        'planId': planId,
        'planName': planName,
        'paymentMethod': selectedMethod,
        'proofUrl': proofUrl ?? '',
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'userEmail': FirebaseAuth.instance.currentUser?.email ?? '',
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Payment submitted! Awaiting admin approval for $planName plan.'),
          backgroundColor: const Color(0xFF6366F1),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _showPlanDialog(BuildContext context, {String? id, Map<String, dynamic>? existing}) {
    final cardColor = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final borderColor = widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final nameCtrl    = TextEditingController(text: existing?['name']);
    final priceCtrl   = TextEditingController(text: (existing?['price'] ?? '').toString());
    final limitCtrl   = TextEditingController(text: (existing?['deviceLimit'] ?? '').toString());
    final blockedCtrl = TextEditingController(text: (existing?['blockedAppsLimit'] ?? '5').toString());
    final hiddenCtrl  = TextEditingController(text: (existing?['hiddenAppsLimit'] ?? '2').toString());
    final colorCtrl   = TextEditingController(text: existing?['color'] ?? '0xFF6366F1');
    final List<TextEditingController> featureCtrls = ((existing?['features'] as List?) ?? ['']).map((f) => TextEditingController(text: f.toString())).toList();

    final Map<String, dynamic> existingFeats = (existing?['featuresMap'] is Map)
        ? Map<String, dynamic>.from(existing!['featuresMap'] as Map)
        : <String, dynamic>{};
    final Map<String, bool> toggles = {
      'appRestrictions':  (existingFeats['appRestrictions']  as bool?) ?? true,
      'scheduleLock':     (existingFeats['scheduleLock']     as bool?) ?? true,
      'appFilter':        (existingFeats['appFilter']        as bool?) ?? true,
      'childMonitoring':  (existingFeats['childMonitoring']  as bool?) ?? true,
      'liveLocation':     (existingFeats['liveLocation']     as bool?) ?? true,
      'chat':             (existingFeats['chat']             as bool?) ?? true,
      'masterPin':        (existingFeats['masterPin']        as bool?) ?? true,
    };
    const Map<String, String> toggleLabels = {
      'appRestrictions':  'App Restrictions',
      'scheduleLock':     'Schedule Lock',
      'appFilter':        'App Filter',
      'childMonitoring':  'Child Activity Monitoring',
      'liveLocation':     'Live Location',
      'chat':             'Parent ↔ Child Chat',
      'masterPin':        'Master PIN',
    };

    String durationUnit = existing?['durationUnit'] ?? 'months';
    int durationValue   = existing?['durationValue'] ?? 1;
    final durValueCtrl  = TextEditingController(text: durationValue.toString());

    Widget field(String label, TextEditingController ctrl, {bool isNum = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl, keyboardType: isNum ? TextInputType.number : TextInputType.text,
        style: GoogleFonts.outfit(color: textColor),
        decoration: InputDecoration(
          labelText: label, labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor.withOpacity(0.5))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1))),
        ),
      ),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(id == null ? 'Create New Plan' : 'Edit Plan', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              field('Plan Name', nameCtrl),
              field(r'Price ($)', priceCtrl, isNum: true),
              field('Max Devices', limitCtrl, isNum: true),
              field('Max Restricted Apps', blockedCtrl, isNum: true),
              field('Max Filtered Apps', hiddenCtrl, isNum: true),
              field('Hex Color (e.g. 0xFF6366F1)', colorCtrl),
              const SizedBox(height: 4),
              Text('PLAN DURATION', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: borderColor.withOpacity(0.5)), borderRadius: BorderRadius.circular(12), color: cardColor),
                child: DropdownButton<String>(
                  value: durationUnit,
                  isExpanded: true,
                  underline: const SizedBox(),
                  dropdownColor: cardColor,
                  style: GoogleFonts.outfit(color: textColor, fontSize: 14),
                  items: const [
                    DropdownMenuItem(value: 'days',     child: Text('Days (1–30)')),
                    DropdownMenuItem(value: 'months',   child: Text('Months')),
                    DropdownMenuItem(value: 'years',    child: Text('Years')),
                    DropdownMenuItem(value: 'lifetime', child: Text('Lifetime')),
                  ],
                  onChanged: (v) { if (v != null) setS(() { durationUnit = v; durationValue = 1; durValueCtrl.text = '1'; }); },
                ),
              ),
              const SizedBox(height: 12),
              if (durationUnit == 'days') ...[
                Text('SELECT DAYS', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.4)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: List.generate(30, (i) {
                  final v = i + 1; final sel = durationValue == v;
                  return GestureDetector(
                    onTap: () => setS(() { durationValue = v; durValueCtrl.text = v.toString(); }),
                    child: Container(
                      width: 38, height: 34,
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF6366F1) : const Color(0xFF6366F1).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF6366F1).withOpacity(sel ? 1 : 0.3)),
                      ),
                      child: Center(child: Text('$v', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? Colors.white : const Color(0xFF6366F1)))),
                    ),
                  );
                })),
              ] else if (durationUnit == 'lifetime')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFBBF24).withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.4))),
                  child: Row(children: [
                    const Icon(Icons.all_inclusive_rounded, color: Color(0xFFFBBF24), size: 20),
                    const SizedBox(width: 8),
                    Text('Access never expires', style: GoogleFonts.outfit(color: const Color(0xFFFBBF24), fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                )
              else
                field(durationUnit == 'months' ? 'Number of Months' : 'Number of Years', durValueCtrl, isNum: true),
              const SizedBox(height: 12),
              Text('FEATURE ACCESS', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: borderColor.withOpacity(0.5)), borderRadius: BorderRadius.circular(12)),
                child: Column(children: toggles.keys.map((k) => SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(toggleLabels[k] ?? k, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
                  value: toggles[k] ?? true,
                  activeColor: const Color(0xFF6366F1),
                  onChanged: (v) => setS(() => toggles[k] = v),
                )).toList()),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Text('MARKETING BULLETS', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
                const Spacer(),
                IconButton(onPressed: () => setS(() => featureCtrls.add(TextEditingController())), icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF6366F1))),
              ]),
              ...featureCtrls.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: field('Feature ${entry.key + 1}', entry.value)),
                  IconButton(onPressed: () => setS(() => featureCtrls.removeAt(entry.key)), icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: Colors.redAccent)),
                ]),
              )).toList(),
            ])),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final parsedDurValue = durationUnit == 'lifetime' ? 0 : (int.tryParse(durValueCtrl.text) ?? durationValue).clamp(1, durationUnit == 'days' ? 30 : 999);
                final planData = {
                  'name': nameCtrl.text.trim(),
                  'price': double.tryParse(priceCtrl.text) ?? 0.0,
                  'deviceLimit': int.tryParse(limitCtrl.text) ?? 1,
                  'blockedAppsLimit': int.tryParse(blockedCtrl.text) ?? 0,
                  'hiddenAppsLimit': int.tryParse(hiddenCtrl.text) ?? 0,
                  'features': featureCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
                  'featuresMap': Map<String, dynamic>.from(toggles),
                  'color': colorCtrl.text.trim(),
                  'durationUnit': durationUnit,
                  'durationValue': parsedDurValue,
                };
                if (id == null) {
                  await FirebaseFirestore.instance.collection('plans').doc(nameCtrl.text.trim().toLowerCase()).set(planData);
                } else {
                  await FirebaseFirestore.instance.collection('plans').doc(id).update(planData);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text('Save Plan', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final currentPlan = (userData['plan'] ?? 'free').toString().toLowerCase();
        final expiryDate = (userData['expiryDate'] as Timestamp?)?.toDate();
        final bool isExpired = expiryDate != null && expiryDate.isBefore(DateTime.now());

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('plans').orderBy('deviceLimit').snapshots(),
          builder: (context, snap) {
            final plans = snap.hasData ? snap.data!.docs : <QueryDocumentSnapshot>[];
            // Build a price map from the plans list for UPGRADE/DOWNGRADE comparison
            final planPriceMap = <String, num>{for (final doc in plans) doc.id.toLowerCase(): (doc.data() as Map<String, dynamic>)['price'] as num? ?? 0};
            final currentPlanPrice = planPriceMap[currentPlan] ?? 0;

            if (_selectedPlan != null) {
              final p = _selectedPlan!;
              final name = (p['name'] ?? 'Plan').toString().toUpperCase();
              final selectedPrice = (p['price'] as num? ?? 0);
              final devices = p['deviceLimit'] ?? 1;
              final blocked = p['blockedAppsLimit'] ?? 0; final hidden = p['hiddenAppsLimit'] ?? 0;
              final hasTracking = p['realtimeTracking'] == true || p['deviceLimit'] == 999;
              final color = p['_color'] as Color? ?? const Color(0xFF22C55E);
              final icon = p['_icon'] as IconData? ?? Icons.workspace_premium_rounded;
              final planId = _selectedPlanId ?? '';
              final isCurrent = currentPlan == planId.toLowerCase() && !isExpired;
              final btnLabel = isCurrent ? 'CURRENT PLAN' : (selectedPrice >= currentPlanPrice ? 'UPGRADE' : 'DOWNGRADE');

              final customFeatures = (p['features'] as List?)?.map((f) => f.toString()).toList() ?? [];
              final durationSuffix = _planDurationLabel(p);

              return Container(
                color: bg,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextButton.icon(
                      onPressed: () => setState(() { _selectedPlan = null; _selectedPlanId = null; }),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18), label: Text('Back', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF94A3B8), padding: EdgeInsets.zero)),
                    const SizedBox(height: 16),
                    if (isCurrent)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                        child: Text('CURRENT PLAN', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
                      ),
                    Text(name, style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w900, color: textColor)),
                    const SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('\$', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
                      Text('${(p['price'] as num? ?? 0).toInt()}', style: GoogleFonts.outfit(fontSize: 38, fontWeight: FontWeight.w900, color: textColor, height: 1)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(durationSuffix, style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF94A3B8))),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    Text('${devices == 999 ? 'Unlimited' : devices} Device${devices == 1 ? '' : 's'}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
                    if (blocked > 0) ...[const SizedBox(height: 4), Text('$blocked Restricted Apps allowed', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: color.withOpacity(0.85)))],
                    if (hidden > 0) ...[const SizedBox(height: 4), Text('$hidden Filtered Apps allowed', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: color.withOpacity(0.85)))],
                    if (hasTracking) ...[const SizedBox(height: 4), Text('Family Location', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: color.withOpacity(0.85)))],
                    if (customFeatures.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Divider(color: const Color(0xFF64748B).withOpacity(0.25)),
                      const SizedBox(height: 16),
                      ...customFeatures.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(children: [
                          Icon(Icons.check_circle_rounded, size: 20, color: color),
                          const SizedBox(width: 12),
                          Expanded(child: Text(f, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: textColor))),
                        ]),
                      )),
                    ],
                    const SizedBox(height: 24),
                    if (!isCurrent)
                      GestureDetector(
                        onTap: () => _upgradePlan(context, planId, (p['name'] ?? 'Plan').toString()),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
                          child: Center(child: Text(btnLabel, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5))),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.4))),
                        child: Center(child: Text('CURRENT PLAN', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.5))),
                      ),
                  ]),
                ),
              );
            }

            if (!snap.hasData) return const Center(child: CircularProgressIndicator());

            final isAdmin = widget.userRole == 'super_admin';
            return Container(
              color: bg,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Subscription Plans', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
                      Text('Active: ${currentPlan.toUpperCase()}${isExpired ? ' (EXPIRED)' : ''}', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8))),
                    ])),
                    if (isAdmin) GestureDetector(
                      onTap: () => _showPlanDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text('Add Plan', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  ...plans.map((doc) {
                    final p = doc.data() as Map<String, dynamic>;
                    final name = (p['name'] ?? 'Plan').toString();
                    final price = p['price'] ?? 0; final devices = p['deviceLimit'] ?? 1;
                    final key = name.toLowerCase();
                    final color = _planColors[key] ?? const Color(0xFF6366F1);
                    final icon = _planIcons[key] ?? Icons.workspace_premium_rounded;
                    final isLifetime = key.contains('lifetime');
                    final isCurrent = currentPlan == doc.id.toLowerCase() && !isExpired;
                    return GestureDetector(
                      onTap: isAdmin ? null : () => setState(() { _selectedPlan = {...p, '_color': color, '_icon': icon}; _selectedPlanId = doc.id; }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: EdgeInsets.only(left: 16, right: isAdmin ? 4 : 8, top: 14, bottom: 14),
                        decoration: BoxDecoration(
                          color: isCurrent ? color.withOpacity(widget.isDark ? 0.15 : 0.07) : (widget.isDark ? const Color(0xFF0F1A35) : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isCurrent ? color : color.withOpacity(0.4), width: isCurrent ? 2 : 1),
                        ),
                        child: Row(children: [
                          Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: textColor)),
                            if (isCurrent) Text('CURRENT PLAN', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w900, color: color)),
                          ])),
                          RichText(text: TextSpan(children: [
                            TextSpan(text: '\$', style: GoogleFonts.outfit(fontSize: 11, color: textColor, fontWeight: FontWeight.w700)),
                            TextSpan(text: '$price', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
                            TextSpan(text: '\n${_planDurationLabel(p)}', style: GoogleFonts.outfit(fontSize: 9, color: const Color(0xFF94A3B8))),
                          ])),
                          const SizedBox(width: 8),
                          if (isAdmin) ...[
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () => _showPlanDialog(context, id: doc.id, existing: {...p}),
                              icon: const Icon(Icons.edit_rounded, color: Color(0xFF6366F1), size: 18),
                              tooltip: 'Edit Plan',
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () async {
                                final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                                  backgroundColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                                  title: Text('Delete $name?', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: textColor)),
                                  content: Text('This will permanently remove this plan.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
                                    ElevatedButton(onPressed: () => Navigator.pop(_, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white))),
                                  ],
                                ));
                                if (ok == true) await FirebaseFirestore.instance.collection('plans').doc(doc.id).delete();
                              },
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                              tooltip: 'Delete Plan',
                            ),
                          ] else
                            Container(width: 34, height: 34, decoration: BoxDecoration(color: isCurrent ? color.withOpacity(0.2) : const Color(0xFF94A3B8).withOpacity(0.15), shape: BoxShape.circle), child: Icon(isCurrent ? Icons.check_rounded : Icons.arrow_forward_rounded, color: isCurrent ? color : const Color(0xFF94A3B8), size: 16)),
                        ]),
                      ),
                    );
                  }),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _bullet(String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [Icon(Icons.circle, size: 6, color: color), const SizedBox(width: 10), Text(text, style: GoogleFonts.outfit(fontSize: 14, color: color, fontWeight: FontWeight.w700))]),
  );

  String _planDurationLabel(Map<String, dynamic> p) {
    final unit  = (p['durationUnit'] ?? '').toString();
    final value = (p['durationValue'] as num?)?.toInt() ?? 1;
    if (unit == 'lifetime') return 'one-time';
    if (unit == 'days')     return value == 1 ? '/day'  : '/$value days';
    if (unit == 'years')    return value == 1 ? '/yr'   : '/$value yrs';
    // default months
    return value == 1 ? '/mo' : '/$value mo';
  }
}

// ─── Settings ─────────────────────────────────────────────────────────────────
class _MobileSettingsView extends StatefulWidget {
  final bool isDark;
  const _MobileSettingsView({required this.isDark});
  @override State<_MobileSettingsView> createState() => _MobileSettingsViewState();
}
class _MobileSettingsViewState extends State<_MobileSettingsView> {
  final _imageUrlCtrl = TextEditingController();
  final _quoteCtrl = TextEditingController();
  final _greetingCtrl = TextEditingController();
  final _headingCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _tasksCtrl = TextEditingController();
  final _rHeadCtrl = TextEditingController();
  final _rMsgCtrl = TextEditingController();
  final _rTasksCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String? _selDevice;
  bool _loaded = false, _saving = false;

  @override void initState() {
    super.initState();
    for (var c in [_imageUrlCtrl, _quoteCtrl, _greetingCtrl, _headingCtrl, _titleCtrl, _tasksCtrl, _rHeadCtrl, _rMsgCtrl, _rTasksCtrl]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }
  @override void dispose() {
    for (var c in [_imageUrlCtrl, _quoteCtrl, _greetingCtrl, _headingCtrl, _titleCtrl, _tasksCtrl, _rHeadCtrl, _rMsgCtrl, _rTasksCtrl, _pinCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid; if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final role = data['role'] ?? 'parent';
    final devices = role == 'super_admin'
        ? await FirebaseFirestore.instance.collection('devices').limit(1).get()
        : await FirebaseFirestore.instance.collection('devices').where('parentUid', isEqualTo: uid).limit(1).get();
    setState(() {
      _imageUrlCtrl.text = data['profileImageUrl'] ?? '';
      _quoteCtrl.text = data['parentQuote'] ?? '';
      _greetingCtrl.text = data['unlockGreeting'] ?? '';
      _headingCtrl.text = data['lockScreenHeading'] ?? 'LOCKED';
      _titleCtrl.text = data['lockScreenTitle'] ?? 'Your Tasks';
      _tasksCtrl.text = (data['lockScreenTasks'] as List<dynamic>? ?? []).join('\n');
      _rHeadCtrl.text = data['restrictedHeadline'] ?? 'APP RESTRICTED';
      _rMsgCtrl.text = data['restrictedMessage'] ?? 'Access to this application is restricted by parent settings.';
      _rTasksCtrl.text = (data['restrictedTasks'] as List<dynamic>? ?? []).join('\n');
      _pinCtrl.text = data['masterPin'] ?? '';
      if (devices.docs.isNotEmpty) {
        _selDevice = devices.docs.first.id;
        _applyDeviceSettings(devices.docs.first.data());
      }
      _loaded = true;
    });
  }

  void _applyDeviceSettings(Map<String, dynamic> data) {
    _imageUrlCtrl.text = data['profileImageUrl'] ?? _imageUrlCtrl.text;
    _quoteCtrl.text = data['parentQuote'] ?? _quoteCtrl.text;
    _greetingCtrl.text = data['unlockGreeting'] ?? _greetingCtrl.text;
    _headingCtrl.text = data['lockHeadline'] ?? data['lockScreenHeading'] ?? _headingCtrl.text;
    _titleCtrl.text = data['taskTitle'] ?? data['lockScreenTitle'] ?? _titleCtrl.text;
    _tasksCtrl.text = (data['taskList'] as List? ?? data['lockScreenTasks'] as List? ?? []).join('\n');
    _rHeadCtrl.text = data['restrictedHeadline'] ?? _rHeadCtrl.text;
    _rMsgCtrl.text = data['restrictedMessage'] ?? _rMsgCtrl.text;
    _rTasksCtrl.text = (data['warningList'] as List? ?? data['restrictedTasks'] as List? ?? []).join('\n');
    _pinCtrl.text = data['pin'] ?? _pinCtrl.text;
  }

  Future<void> _save(String section) async {
    final uid = FirebaseAuth.instance.currentUser?.uid; if (uid == null) return;
    setState(() => _saving = true);
    Map<String, dynamic> payload = {};
    Map<String, dynamic>? devicePayload;
    if (section == 'child') {
      payload = {
        'profileImageUrl': _imageUrlCtrl.text.trim(),
        'parentQuote': _quoteCtrl.text.trim(),
        'unlockGreeting': _greetingCtrl.text.trim(),
      };
      devicePayload = payload;
    }
    else if (section == 'lock') {
      final tasks = _tasksCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
      payload = {'lockScreenHeading': _headingCtrl.text.trim(), 'lockScreenTitle': _titleCtrl.text.trim(), 'lockScreenTasks': tasks};
      devicePayload = {'lockHeadline': _headingCtrl.text.trim(), 'taskTitle': _titleCtrl.text.trim(), 'taskList': tasks};
    } else if (section == 'restrict') {
      final tasks = _rTasksCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
      payload = {'restrictedHeadline': _rHeadCtrl.text.trim(), 'restrictedMessage': _rMsgCtrl.text.trim(), 'restrictedTasks': tasks};
      devicePayload = {'restrictedHeadline': _rHeadCtrl.text.trim(), 'restrictedMessage': _rMsgCtrl.text.trim(), 'warningList': tasks};
    } else if (section == 'pin') {
      final pin = _pinCtrl.text.trim();
      payload = {'masterPin': pin};
      final devices = await FirebaseFirestore.instance.collection('devices').where('parentUid', isEqualTo: uid).get();
      for (final d in devices.docs) {
        await d.reference.update({'pin': pin}).catchError((_) {});
      }
    }
    try {
      if (devicePayload != null && _selDevice != null) {
        await FirebaseFirestore.instance.collection('devices').doc(_selDevice).update(devicePayload);
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).set(payload, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved successfully!'), backgroundColor: Color(0xFF22C55E)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.click();
    await input.onChange.first;
    final file = input.files?.first; if (file == null) return;
    final reader = html.FileReader(); reader.readAsArrayBuffer(file); await reader.onLoad.first;
    final bytes = reader.result as List<int>;
    final uid = FirebaseAuth.instance.currentUser?.uid; if (uid == null) return;
    final ref = FirebaseStorage.instance.ref('profile_images/$uid/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
    await ref.putData(Uint8List.fromList(bytes), SettableMetadata(contentType: file.type));
    final url = await ref.getDownloadURL();
    setState(() => _imageUrlCtrl.text = url);
  }

  Widget _buildLockPhoneMockup({required String heading, required String title, required List<String> tasks}) {
    return Container(
      width: 110,
      height: 210,
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B), width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(children: [
          Container(height: 10, color: const Color(0xFF1E293B), child: Center(child: Container(width: 28, height: 4, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(2))))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(children: [
                Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1E293B), width: 1.5)), child: const Icon(Icons.add, size: 12, color: Color(0xFF1E293B))),
                const SizedBox(height: 4),
                Text(heading, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B), letterSpacing: 1)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(6)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: GoogleFonts.outfit(fontSize: 6, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                    const SizedBox(height: 2),
                    ...tasks.take(3).map((t) => Text(t, style: GoogleFonts.outfit(fontSize: 5, color: const Color(0xFF374151)), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(6)),
                  child: Text('SEND MESSAGE HERE', style: GoogleFonts.outfit(fontSize: 5, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.center),
                ),
                const SizedBox(height: 4),
                Text('This device is managed by\nyour parent', style: GoogleFonts.outfit(fontSize: 4.5, color: const Color(0xFF374151)), textAlign: TextAlign.center),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildRestrictedPhoneMockup({required String headline, required List<String> tasks}) {
    return Container(
      width: 110,
      height: 210,
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B), width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(children: [
          Container(height: 10, color: const Color(0xFF1E293B), child: Center(child: Container(width: 28, height: 4, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(2))))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(children: [
                const Icon(Icons.warning_amber_rounded, size: 22, color: Colors.white),
                const SizedBox(height: 2),
                Text(headline, style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(6)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('YOUR TASKS', style: GoogleFonts.outfit(fontSize: 5.5, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 2),
                    ...tasks.take(2).map((t) => Text(t, style: GoogleFonts.outfit(fontSize: 5, color: Colors.white70), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                  child: Text('GOT IT', style: GoogleFonts.outfit(fontSize: 6, fontWeight: FontWeight.w800, color: const Color(0xFFEF4444)), textAlign: TextAlign.center),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  void _showLockPreviewDialog() {
    final tasks = _tasksCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final heading = _headingCtrl.text.isEmpty ? 'LOCKED' : _headingCtrl.text;
    final title = _titleCtrl.text.isEmpty ? 'Parent Tasks' : _titleCtrl.text;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: widget.isDark ? const Color(0xFF0F1A35) : Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.5))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Lock Screen Preview', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: widget.isDark ? Colors.white : const Color(0xFF1E293B))),
            const SizedBox(height: 16),
            Container(
              width: 200, height: 360,
              decoration: BoxDecoration(color: const Color(0xFFFBBF24), borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFF1E293B), width: 4)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(children: [
                  Container(height: 16, color: const Color(0xFF1E293B), child: Center(child: Container(width: 40, height: 6, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(3))))),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1E293B), width: 2)), child: const Icon(Icons.add, color: Color(0xFF1E293B))),
                        const SizedBox(height: 10),
                        Text(heading, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B), letterSpacing: 2)),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(10)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('YOUR TASKS', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B))),
                            Text(title, style: GoogleFonts.outfit(fontSize: 8, color: const Color(0xFF374151))),
                            const SizedBox(height: 6),
                            ...tasks.take(4).map((t) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('• $t', style: GoogleFonts.outfit(fontSize: 9, color: const Color(0xFF374151))))),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.send_rounded, color: Colors.white, size: 14), const SizedBox(width: 6), Text('SEND MESSAGE HERE', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))]),
                        ),
                        const SizedBox(height: 8),
                        Text('This device is managed by your parent.\nComplete tasks to unlock.', style: GoogleFonts.outfit(fontSize: 9, color: const Color(0xFF374151)), textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: GoogleFonts.outfit(color: const Color(0xFF22C55E), fontWeight: FontWeight.w700))),
          ]),
        ),
      ),
    );
  }

  void _showRestrictedPreviewDialog() {
    final tasks = _rTasksCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final headline = _rHeadCtrl.text.isEmpty ? 'APP RESTRICTED' : _rHeadCtrl.text;
    final msg = _rMsgCtrl.text.isEmpty ? 'Access to this application is restricted by parent settings.' : _rMsgCtrl.text;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: widget.isDark ? const Color(0xFF0F1A35) : Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('App Restricted Preview', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: widget.isDark ? Colors.white : const Color(0xFF1E293B))),
            const SizedBox(height: 16),
            Container(
              width: 200, height: 360,
              decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFF1E293B), width: 4)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(children: [
                  Container(height: 16, color: const Color(0xFF1E293B), child: Center(child: Container(width: 40, height: 6, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(3))))),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.warning_amber_rounded, size: 36, color: Colors.white)),
                        const SizedBox(height: 12),
                        Text(headline, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1), textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(msg, style: GoogleFonts.outfit(fontSize: 9, color: Colors.white70), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        if (tasks.isNotEmpty) Container(
                          width: double.infinity, padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('YOUR TASKS', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
                            const SizedBox(height: 4),
                            ...tasks.take(4).map((t) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('• $t', style: GoogleFonts.outfit(fontSize: 9, color: Colors.white70)))),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                          child: Text('GOT IT', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFFEF4444)), textAlign: TextAlign.center),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontWeight: FontWeight.w700))),
          ]),
        ),
      ),
    );
  }

  Widget _sectionWrap(String title, String sectionId, Widget body, {bool showSave = true}) {
    final sectionBg = widget.isDark ? const Color(0xFF091526) : const Color(0xFFECFDF5);
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: textColor)),
        const Spacer(),
        if (showSave) GestureDetector(
          onTap: _saving ? null : () => _save(sectionId),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(20)),
            child: Text(_saving ? '...' : 'save', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
        ),
      ]),
      const SizedBox(height: 10),
      Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: sectionBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3))), child: body),
      const SizedBox(height: 20),
    ]);
  }

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1, String? hint}) {
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final bg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(controller: ctrl, maxLines: maxLines, style: GoogleFonts.outfit(fontSize: 13, color: textColor),
        decoration: InputDecoration(hintText: hint, hintStyle: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)), filled: true, fillColor: bg, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: border, enabledBorder: border, focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.5)))),
      const SizedBox(height: 10),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    if (!_loaded) return Container(color: bg, child: const Center(child: CircularProgressIndicator()));

    return Container(
      color: bg,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionWrap('Child App View Data', 'child', Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.instance.streamAdminDevices(),
                builder: (context, snap) {
                  final devices = snap.data?.docs ?? [];
                  if (_selDevice == null && devices.isNotEmpty) {
                    _selDevice = devices.first.id;
                  }
                  final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
                  if (devices.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Target Device', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: widget.isDark ? const Color(0xFF0F1A35) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.8))),
                      child: DropdownButton<String>(
                        value: devices.any((d) => d.id == _selDevice) ? _selDevice : devices.first.id,
                        isExpanded: true,
                        underline: const SizedBox(),
                        dropdownColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                        style: GoogleFonts.outfit(fontSize: 13, color: textColor),
                        items: devices.map((d) => DropdownMenuItem(value: d.id, child: Text(d.id))).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          final doc = devices.firstWhere((d) => d.id == v);
                          setState(() {
                            _selDevice = v;
                            _applyDeviceSettings(doc.data() as Map<String, dynamic>);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ]);
                },
              ),
              _tf('Paste your URL here', _imageUrlCtrl, hint: 'https://example.com/photo.jpg'),
              _tf('Parent Quote', _quoteCtrl, maxLines: 3, hint: '"I love you more than words can say"'),
              _tf('Unlock Greetings', _greetingCtrl, hint: 'Enjoy Your Day My Child.'),
            ])),
            const SizedBox(width: 10),
            Column(children: [
              Container(width: 88, height: 110, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: widget.isDark ? Colors.white10 : const Color(0xFFE2E8F0)), clipBehavior: Clip.hardEdge,
                child: _imageUrlCtrl.text.isNotEmpty ? Image.network(_imageUrlCtrl.text, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 36, color: Color(0xFF94A3B8))) : const Icon(Icons.person_rounded, size: 36, color: Color(0xFF94A3B8))),
              const SizedBox(height: 6),
              GestureDetector(onTap: _pickImage,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFFBBF24), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.upload_rounded, color: Colors.white, size: 14), const SizedBox(width: 4), Text('Choose Img', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))]))),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  final imgUrl = _imageUrlCtrl.text;
                  final quote = _quoteCtrl.text;
                  final greeting = _greetingCtrl.text;
                  showDialog(
                    context: context,
                    builder: (ctx) => Dialog(
                      backgroundColor: Colors.transparent,
                      child: SingleChildScrollView(
                        child: Container(
                          width: 360,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 32, offset: const Offset(0, 8))]),
                          padding: const EdgeInsets.all(20),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            // App header
                            Row(children: [
                              Text('AppLocker', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B))),
                              const SizedBox(width: 8),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(20)), child: Text('v2.0.0+12', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
                              const Spacer(),
                              const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8), size: 24),
                              const SizedBox(width: 14),
                              const Icon(Icons.logout_rounded, color: Color(0xFF94A3B8), size: 24),
                            ]),
                            const SizedBox(height: 14),
                            // Status card
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(color: const Color(0xFFEEEFF8), borderRadius: BorderRadius.circular(16)),
                              child: Row(children: [
                                Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 22)),
                                const SizedBox(width: 12),
                                Text('Online', style: GoogleFonts.outfit(fontSize: 15, color: const Color(0xFF374151))),
                                const Spacer(),
                                const Icon(Icons.battery_full_rounded, color: Color(0xFF22C55E), size: 30),
                                const SizedBox(width: 6),
                                Text('100%', style: GoogleFonts.outfit(fontSize: 15, color: const Color(0xFF374151))),
                              ]),
                            ),
                            const SizedBox(height: 12),
                            // Quote + photo card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: const Color(0xFFEEEFF8), borderRadius: BorderRadius.circular(16)),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Text('♥ ~', style: TextStyle(fontSize: 22, color: Color(0xFFEF4444))),
                                  const SizedBox(height: 8),
                                  Text(
                                    quote.isNotEmpty ? '"$quote"' : '"You are my heart in human form. No matter where life takes you, you will always be my greatest love."',
                                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B), height: 1.4),
                                  ),
                                ])),
                                const SizedBox(width: 12),
                                Container(
                                  width: 105, height: 140,
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF22C55E), width: 2.5)),
                                  clipBehavior: Clip.hardEdge,
                                  child: imgUrl.isNotEmpty
                                    ? Image.network(imgUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 44, color: Color(0xFF94A3B8)))
                                    : const Icon(Icons.person_rounded, size: 44, color: Color(0xFF94A3B8)),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 12),
                            // Device Unlocked card
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                              decoration: BoxDecoration(color: const Color(0xFFEEEFF8), borderRadius: BorderRadius.circular(16)),
                              child: Row(children: [
                                Container(width: 56, height: 56, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.lock_open_rounded, color: Color(0xFF22C55E), size: 32)),
                                const SizedBox(width: 16),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Device Unlocked', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B))),
                                  Text('"${greeting.isNotEmpty ? greeting : 'Enjoy Your Day'}"', style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF374151))),
                                ])),
                              ]),
                            ),
                            const SizedBox(height: 16),
                            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: GoogleFonts.outfit(color: const Color(0xFF22C55E), fontWeight: FontWeight.w700))),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.preview_rounded, color: Colors.white, size: 14), const SizedBox(width: 4), Text('Preview', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))])),
              ),
            ]),
          ])),

          _sectionWrap('Device Lock Screen Settings', 'lock', StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.instance.streamAdminDevices(),
            builder: (context, snap) {
              final devices = snap.data?.docs ?? [];
              _selDevice ??= devices.isNotEmpty ? devices.first.id : null;
              final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
              final tasks = _tasksCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Target Device', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    if (devices.isNotEmpty) Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: widget.isDark ? const Color(0xFF0F1A35) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.8))),
                      child: DropdownButton<String>(
                        value: devices.any((d) => d.id == _selDevice) ? _selDevice : devices.first.id, isExpanded: true, underline: const SizedBox(),
                        dropdownColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                        style: GoogleFonts.outfit(fontSize: 13, color: widget.isDark ? Colors.white : const Color(0xFF1E293B)),
                        items: devices.map((d) => DropdownMenuItem(value: d.id, child: Text(d.id))).toList(),
                        onChanged: (v) => setState(() => _selDevice = v),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text('Lock Screen Heading', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('Core Messaging', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: textColor)),
                    ]),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _headingCtrl,
                      style: GoogleFonts.outfit(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'LOCKED',
                        hintStyle: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                        filled: true, fillColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _tf('Lock Screen Title', _titleCtrl, hint: 'Parent Tasks'),
                    _tf('Lock Screen Task  (One per line )', _tasksCtrl, maxLines: 5, hint: 'Cook Food\nBreakfast\nWash Dishes\nClean House'),
                  ]),
                ),
                const SizedBox(width: 12),
                Column(children: [
                  _buildLockPhoneMockup(
                    heading: _headingCtrl.text.isEmpty ? 'LOCKED' : _headingCtrl.text,
                    title: _titleCtrl.text.isEmpty ? 'YOUR TASKS' : _titleCtrl.text.toUpperCase(),
                    tasks: tasks.isEmpty ? ['Cook Food 11:00AM', 'Lunch 12:00 AM', 'Wash Dishes 12:30 PM'] : tasks,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showLockPreviewDialog(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(10)),
                      child: Text('Preview', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ]),
              ]);
            },
          )),

          _sectionWrap('App Restricted Settings', 'restrict', Builder(builder: (context) {
            final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
            final rTasks = _rTasksCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('App Restricted Headline', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('Core Messaging', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: textColor)),
                  ]),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _rHeadCtrl,
                    style: GoogleFonts.outfit(fontSize: 13, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'APP RESTRICTED',
                      hintStyle: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                      filled: true, fillColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _tf('App Restricted Fallback Message', _rMsgCtrl, maxLines: 2, hint: 'Access to this application is restricted by parent settings.'),
                  Row(children: [
                    Expanded(child: Text('List of Task to Show  (one per line)', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600))),
                    const SizedBox(width: 4),
                    Text('Restricted Task List', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: textColor)),
                  ]),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _rTasksCtrl,
                    maxLines: 5,
                    style: GoogleFonts.outfit(fontSize: 13, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Cook Food\nBreakfast\nWash Dishes\nClean House',
                      hintStyle: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                      filled: true, fillColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ]),
              ),
              const SizedBox(width: 12),
              Column(children: [
                _buildRestrictedPhoneMockup(
                  headline: _rHeadCtrl.text.isEmpty ? 'RESTRICTED' : _rHeadCtrl.text,
                  tasks: rTasks.isEmpty ? ['Cook Food 11:00AM', 'Lunch 12:00 AM'] : rTasks,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _showRestrictedPreviewDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(10)),
                    child: Text('Preview', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ]),
            ]);
          })),

          _sectionWrap('Default Master PIN', 'pin', Row(children: [
            Expanded(child: TextField(
              controller: _pinCtrl,
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: widget.isDark ? Colors.white : const Color(0xFF1E293B)),
              textAlign: TextAlign.center, keyboardType: TextInputType.number,
              decoration: InputDecoration(filled: true, fillColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white, contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E)))),
            )),
            const SizedBox(width: 10),
            GestureDetector(onTap: () => _save('pin'),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(10)),
                child: Text('save', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)))),
          ]), showSave: false),
        ]),
      ),
    );
  }

}

class _StatCard extends StatelessWidget {
  final String title; final String value; final HeroIcons icon; final Color color; final bool isDark;
  const _StatCard({required this.title, required this.value, required this.icon, required this.color, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? color.withOpacity(0.12) : color.withOpacity(0.06); 
    final valueColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final labelColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(24), 
      decoration: BoxDecoration(
        color: bgColor, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Stack(
        children: [
          // Icon - Top Right
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12), 
              decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle), 
              child: HeroIcon(icon, size: 28, color: color, style: HeroIconStyle.solid)
            ),
          ),
          
          // Value - Middle Left
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              value, 
              style: GoogleFonts.outfit(
                fontSize: 42, 
                fontWeight: FontWeight.w900, 
                color: valueColor,
                letterSpacing: -1
              )
            ),
          ),
          
          // Title - Bottom Middle
          Align(
            alignment: Alignment.bottomCenter,
            child: Text(
              title.toUpperCase(), 
              style: GoogleFonts.outfit(
                fontSize: 12, 
                fontWeight: FontWeight.w900, 
                color: labelColor, 
                letterSpacing: 2
              ), 
              maxLines: 1
            ),
          ),
        ],
      ),
    );
  }
}

// --- NEW SUPER ADMIN DASHBOARD ---
class _SuperAdminDashboard extends StatelessWidget {
  final bool isDark;
  final bool isMobile;
  const _SuperAdminDashboard({required this.isDark, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, userSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('devices').snapshots(),
          builder: (context, deviceSnapshot) {
            final users = userSnapshot.data?.docs ?? [];
            final devices = deviceSnapshot.data?.docs ?? [];
            final online = devices.where((d) => (d.data() as Map)['status'] == 'online').length;
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Hero Welcome Header
                _buildSuperHeader(users.length, textColor),
                const SizedBox(height: 32),

                // 2. Global Key Metrics
                _buildGlobalMetrics(users.length, devices.length, online, textColor),
                const SizedBox(height: 48),

                // 3. Charts Section
                if (isMobile) 
                  Column(children: [
                    _buildLineChartCard(devices, textColor, isMobile, isDark),
                    const SizedBox(height: 24),
                    _buildPieChartCard(users, textColor, isMobile, isDark),
                  ])
                else 
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: _buildLineChartCard(devices, textColor, isMobile, isDark)),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: _buildPieChartCard(users, textColor, isMobile, isDark)),
                  ]),
                  
                const SizedBox(height: 48),
                
                // 4. Recent Activity Log
                _buildHistoryLog(users, textColor),
                const SizedBox(height: 100),
              ],
            );
          }
        );
      }
    );
  }

  Widget _buildSuperHeader(int userCount, Color textColor) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 24 : 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark ? [const Color(0xFF6366F1), const Color(0xFF8B5CF6)] : [const Color(0xFF4F46E5), const Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 20))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text('COMMAND CENTER', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                ),
                const SizedBox(height: 16),
                Text('Global System Overview', style: GoogleFonts.outfit(fontSize: isMobile ? 20 : 36, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 8),
                Text('Currently presiding over $userCount active accounts across all platforms.', style: GoogleFonts.outfit(fontSize: 14, color: Colors.white.withOpacity(0.8))),
              ],
            ),
          ),
          if (!isMobile) const HeroIcon(HeroIcons.cpuChip, size: 80, color: Colors.white24),
        ],
      ),
    );
  }

  Widget _buildGlobalMetrics(int users, int devices, int online, Color textColor) {
    return LayoutBuilder(builder: (context, constraints) {
      int count = constraints.maxWidth < 600 ? 2 : (constraints.maxWidth < 1100 ? 2 : 4);
      return GridView.count(
        crossAxisCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: constraints.maxWidth < 600 ? 1.4 : 2.0,
        children: [
          _AdminStatItem(title: 'TOTAL USERS', value: users.toString(), icon: HeroIcons.users, color: Colors.orange),
          _AdminStatItem(title: 'GLOBAL DEVICES', value: devices.toString(), icon: HeroIcons.devicePhoneMobile, color: Colors.blue),
          _AdminStatItem(title: 'ONLINE NOW', value: online.toString(), icon: HeroIcons.signal, color: Colors.green),
          _AdminStatItem(title: 'SYSTEM HEALTH', value: '99.9%', icon: HeroIcons.checkBadge, color: Colors.purple),
        ],
      );
    });
  }

  Widget _buildHistoryLog(List<QueryDocumentSnapshot> users, Color textColor) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: textColor.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('GLOBAL ACCOUNT ACCESS', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 1)),
              const Spacer(),
              const Icon(Icons.more_horiz_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
          const SizedBox(height: 32),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: users.take(5).length,
            separatorBuilder: (_, __) => Divider(color: textColor.withOpacity(0.05)),
            itemBuilder: (context, index) {
              final user = users[index].data() as Map<String, dynamic>;
              final email = user['email'] ?? 'Unknown User';
              final role = user['role'] ?? 'parent';
              final plan = user['plan'] ?? 'free';
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(backgroundColor: const Color(0xFF6366F1).withOpacity(0.1), child: Text(email[0].toUpperCase(), style: const TextStyle(color: Color(0xFF6366F1)))),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(email, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textColor, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(role.toString().toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: (plan.toString().toLowerCase() == 'pro' ? Colors.blue : Colors.grey).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(plan.toString().toUpperCase(), style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: plan.toString().toLowerCase() == 'pro' ? Colors.blue : Colors.grey)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// SHARED CHART WIDGETS
Widget _buildLineChartCard(List<QueryDocumentSnapshot> docs, Color textColor, bool isMobile, bool isDark) {
  return Container(
    padding: EdgeInsets.all(isMobile ? 20 : 32),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF18181B) : Colors.white,
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: textColor.withOpacity(0.2), width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVITY TREND', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 1)),
        const SizedBox(height: 24),
        SizedBox(
          height: isMobile ? 200 : 250,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: false),
              titlesData: FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [const FlSpot(0, 1), const FlSpot(2, 3), const FlSpot(4, 2), const FlSpot(6, 5), const FlSpot(8, 4), const FlSpot(10, 6)],
                  isCurved: true,
                  color: const Color(0xFF6366F1),
                  barWidth: isMobile ? 4 : 6,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: const Color(0xFF6366F1).withOpacity(0.1)),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildPieChartCard(List<QueryDocumentSnapshot> docs, Color textColor, bool isMobile, bool isDark) {
  // For Super Admin, this is Subscriptions. For Parent, this is Device Status.
  bool isAdminView = docs.isNotEmpty && (docs.first.data() as Map).containsKey('status');
  
  double val1 = 0, val2 = 0, val3 = 0;
  String t1 = '', t2 = '', t3 = '';

  if (isAdminView) {
     val1 = docs.where((d) => (d.data() as Map)['status'] == 'online').length.toDouble();
     val2 = docs.length - val1;
     t1 = 'ON'; t2 = 'OFF';
  } else {
     val1 = docs.where((u) => (u.data() as Map)['plan']?.toString().toLowerCase() == 'pro').length.toDouble();
     val2 = docs.where((u) => (u.data() as Map)['plan']?.toString().toLowerCase() == 'starter').length.toDouble();
     val3 = docs.length - val1 - val2;
     t1 = 'PRO'; t2 = 'STR'; t3 = 'FREE';
  }

  return Container(
    padding: EdgeInsets.all(isMobile ? 20 : 32),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF18181B) : Colors.white,
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: textColor.withOpacity(0.2), width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isAdminView ? 'DEVICE REACH' : 'SUBSCRIPTION MIX', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 1)),
        const SizedBox(height: 24),
        SizedBox(
          height: isMobile ? 200 : 250,
          child: PieChart(
            PieChartData(
              sectionsSpace: 8,
              centerSpaceRadius: isMobile ? 40 : 60,
              sections: [
                PieChartSectionData(value: val1 == 0 && val2 == 0 ? 1 : val1, color: const Color(0xFF6366F1), title: t1, radius: 25, titleStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 10)),
                PieChartSectionData(value: val2, color: const Color(0xFF10B981), title: t2, radius: 25, titleStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 10)),
                if (!isAdminView) PieChartSectionData(value: val3, color: const Color(0xFF94A3B8), title: t3, radius: 25, titleStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 10)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _AdminStatItem extends StatelessWidget {
  final String title; final String value; final HeroIcons icon; final Color color;
  const _AdminStatItem({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HeroIcon(icon, size: 24, color: color),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w900, color: color)),
          Text(title, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 1)),
        ],
      ),
    );
  }
}

class _DevicesList extends StatefulWidget {
  final bool isDark; final Color cardColor; final Color textColor; final Color borderColor; final bool isMobile; final String userRole;
  const _DevicesList({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor, required this.isMobile, required this.userRole});
  @override State<_DevicesList> createState() => _DevicesListState();
}

class _DevicesListState extends State<_DevicesList> {
  String? _expandedDeviceId;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snapshot.data!.docs;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(widget.userRole == 'super_admin' ? 'Global Devices' : 'My Devices', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: widget.textColor)), const Spacer(), ElevatedButton.icon(onPressed: () => showAppLockerPairingDialog(context, widget.cardColor, widget.textColor), icon: const Icon(Icons.add_rounded), label: const Text('Add Device'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)))]),
          const SizedBox(height: 24),
          widget.isMobile
              ? ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: devices.length, itemBuilder: (context, index) => _buildDeviceCard(context, devices[index].data() as Map<String, dynamic>, devices[index].id))
              : Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: devices.map((doc) => SizedBox(
                    width: (MediaQuery.of(context).size.width - (32 * 2) - (16 * 2)) / 3 - 1, // Approx 3 columns
                    child: _buildDeviceCard(context, doc.data() as Map<String, dynamic>, doc.id)
                  )).toList(),
                ),
        ]);
      },
    );
  }

  Widget _buildDeviceCard(BuildContext context, Map<String, dynamic> device, String deviceId) {
    return Container(
      margin: widget.isMobile ? const EdgeInsets.only(bottom: 16) : null,
      padding: const EdgeInsets.all(18), 
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF64748B).withOpacity(0.5), width: 1.5), 
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              () {
                final isOnlineDevice = (device['status'] ?? 'offline').toString().toLowerCase() == 'online';
                final circleCol = isOnlineDevice ? const Color(0xFF22C55E) : const Color(0xFF94A3B8);
                return Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: circleCol, shape: BoxShape.circle),
                  child: const Icon(Icons.smartphone_rounded, color: Colors.white, size: 24),
                );
              }(),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(deviceId, style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18, color: widget.textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(
                    color: (device['status'] ?? 'offline').toString().toLowerCase() == 'online' ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                    shape: BoxShape.circle,
                  )),
                  const SizedBox(width: 5),
                  Text((device['status'] ?? 'offline').toString().toLowerCase() == 'online' ? 'Online' : 'Offline',
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700,
                      color: (device['status'] ?? 'offline').toString().toLowerCase() == 'online' ? const Color(0xFF22C55E) : const Color(0xFF94A3B8))),
                ]),
              ])),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                   Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text((device['status'] ?? 'offline').toString().toUpperCase(), style: GoogleFonts.outfit(color: const Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.w900))),
                  const SizedBox(height: 8),
                  InkWell(onTap: () => _removeDevice(deviceId), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(1.0), borderRadius: BorderRadius.circular(10)), child: Text('Remove', style: GoogleFonts.outfit(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)))),
                ],
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [Icon(Icons.battery_charging_full_rounded, size: 16, color: widget.textColor.withOpacity(0.7)), const SizedBox(width: 6), Text('${device['battery'] ?? 0}%', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: widget.textColor))]),
              Flexible(child: _LocationCityItem(lat: (device['lat'] as num?)?.toDouble() ?? 0.0, lng: (device['lng'] as num?)?.toDouble() ?? 0.0, textColor: widget.textColor.withOpacity(0.7), isInline: true)),
              Row(children: [Icon(Icons.wifi_rounded, size: 16, color: widget.textColor.withOpacity(0.7)), const SizedBox(width: 6), Text(deviceId, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: widget.textColor))]),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, thickness: 1.5, color: widget.borderColor.withOpacity(0.25)), // Made horizontal line more prominent
          const SizedBox(height: 16),
          
          Text('ACTIVE LOCK RULES', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
          const SizedBox(height: 12),
          
          if ((device['lockSchedules'] as List<dynamic>? ?? []).isEmpty)
             Text('No active time restrictions', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (device['lockSchedules'] as List<dynamic>).asMap().entries.map((entry) {
                final idx = entry.key;
                final s = entry.value;
                return Container(
                  padding: const EdgeInsets.only(left: 12, right: 6, top: 2, bottom: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEC4899).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF64748B), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_clock_rounded, size: 14, color: Color(0xFFEC4899)),
                      const SizedBox(width: 8),
                      Text('${s['start']} - ${s['end']}', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFEC4899))),
                      IconButton(
                        onPressed: () {
                          final list = List<dynamic>.from(device['lockSchedules'] ?? []);
                          list.removeAt(idx);
                          FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'lockSchedules': list});
                        },
                        icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFEC4899)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          
          const SizedBox(height: 24),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              _buildMiniActionButton(icon: device['locked'] == true ? Icons.lock_open_rounded : Icons.lock_outline_rounded, color: device['locked'] == true ? const Color(0xFF10B981) : const Color(0xFFEF4444), onTap: () => FirebaseService.instance.sendCommand(deviceId: deviceId, command: device['locked'] == true ? 'force_unlock' : 'show_overlay')),
              const SizedBox(width: 12),
              _buildMiniActionButton(icon: Icons.location_on_rounded, color: const Color(0xFF6366F1), onTap: () => _showLocation(context, device)),
              const SizedBox(width: 12),
              _buildMiniActionButton(icon: Icons.message_rounded, color: const Color(0xFFF59E0B), onTap: () => _showChatDialog(context, deviceId)),
              const SizedBox(width: 12),
              _buildMiniActionButton(icon: Icons.history_rounded, color: const Color(0xFF8B5CF6), onTap: () => showDialog(context: context, builder: (_) => AlertDialog(backgroundColor: widget.cardColor, title: const Text('Device Activity History'), content: const Text('Detailed activity history will be populated here as events synchronize from the device.')))),
              const SizedBox(width: 12),
              _buildMiniActionButton(icon: Icons.timer_rounded, color: const Color(0xFFEC4899), onTap: () => _showScheduleDialog(context, deviceId, device)),
            ],
          ),
        ],
      ),
    );
  }

  void _showChatDialog(BuildContext context, String deviceId) {
    final TextEditingController msgCtrl = TextEditingController();
    final ScrollController scrollCtrl = ScrollController();
    bool sending = false;

    void scrollToBottom() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollCtrl.hasClients) {
          scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return Dialog(
            backgroundColor: widget.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 420,
              height: 520,
              padding: const EdgeInsets.all(0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        const Text('💬', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Chat with Child',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black54),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseService.instance.streamChatMessages(deviceId),
                      builder: (context, snapshot) {
                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isNotEmpty) scrollToBottom();
                        if (docs.isEmpty) {
                          return Center(
                            child: Text('No messages yet.',
                                style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
                          );
                        }
                        return ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final data = docs[i].data() as Map<String, dynamic>;
                            final isParent = data['sender'] == 'parent';
                            final text = data['text'] as String? ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisAlignment: isParent
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isParent
                                            ? const Color(0xFF6366F1)
                                            : (widget.isDark ? Colors.white12 : const Color(0xFFF1F5F9)),
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: isParent ? const Radius.circular(16) : const Radius.circular(4),
                                          bottomRight: isParent ? const Radius.circular(4) : const Radius.circular(16),
                                        ),
                                      ),
                                      child: Text(text,
                                          style: GoogleFonts.outfit(
                                            color: isParent ? Colors.white : widget.textColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          )),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: widget.borderColor, width: 1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: msgCtrl,
                            style: GoogleFonts.outfit(color: widget.textColor),
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            onSubmitted: (_) async {
                              final text = msgCtrl.text.trim();
                              if (text.isEmpty || sending) return;
                              setS(() => sending = true);
                              msgCtrl.clear();
                              await FirebaseService.instance.sendChatMessage(deviceId, text, 'parent');
                              setS(() => sending = false);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: sending ? null : () async {
                            final text = msgCtrl.text.trim();
                            if (text.isEmpty) return;
                            setS(() => sending = true);
                            msgCtrl.clear();
                            await FirebaseService.instance.sendChatMessage(deviceId, text, 'parent');
                            setS(() => sending = false);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                          ),
                          child: sending
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      msgCtrl.dispose();
      scrollCtrl.dispose();
      FirebaseService.instance.markMessagesRead(deviceId, 'child');
    });
  }

  void _showScheduleDialog(BuildContext context, String deviceId, Map<String, dynamic> device) {
    final List<dynamic> schedules = device['lockSchedules'] as List<dynamic>? ?? [];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.timer_rounded, color: Color(0xFFEC4899)),
              const SizedBox(width: 12),
              Text('Device Lock Schedules', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 20, color: widget.textColor)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (schedules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('No active schedules for this device.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
                  ),
                ...schedules.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final s = entry.value as Map<String, dynamic>;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: widget.textColor.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_clock_rounded, size: 16, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 12),
                        Expanded(child: Text('${s['start']} - ${s['end']}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: widget.textColor))),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                          onPressed: () {
                            schedules.removeAt(idx);
                            FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'lockSchedules': schedules});
                            setDialogState(() {});
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final start = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (start == null) return;
                    final end = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))));
                    if (end == null) return;
                    
                    final startDt = DateTime(2022, 1, 1, start.hour, start.minute);
                    final endDt = DateTime(2022, 1, 1, end.hour, end.minute);
                    
                    final String startStr = DateFormat('h:mm a').format(startDt);
                    final String endStr = DateFormat('h:mm a').format(endDt);
                    
                    schedules.add({'start': startStr, 'end': endStr, 'enabled': true});
                    FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'lockSchedules': schedules});
                    setDialogState(() {});
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Rule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Done', style: GoogleFonts.outfit(color: const Color(0xFF6366F1), fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniActionButton({required IconData icon, required VoidCallback onTap, required Color color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
  void _showLocation(BuildContext context, Map<String, dynamic> device) { final lat = (device['lat'] as num?)?.toDouble() ?? 0.0, lng = (device['lng'] as num?)?.toDouble() ?? 0.0; showDialog(context: context, builder: (context) => Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), child: Container(height: 500, padding: const EdgeInsets.all(8), child: ClipRRect(borderRadius: BorderRadius.circular(16), child: FlutterMap(options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: 14), children: [TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'), MarkerLayer(markers: [Marker(point: LatLng(lat, lng), width: 60, height: 60, child: const Icon(Icons.location_on_rounded, color: Colors.red, size: 40))])]))))); }
  void _removeDevice(String deviceId) async { final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(backgroundColor: widget.cardColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('Remove Device?'), content: const Text('This will unlink the device and remove all its settings.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.redAccent)))])); if (confirm == true) await FirebaseFirestore.instance.collection('devices').doc(deviceId).delete(); }
}

class _LocationCityItem extends StatefulWidget {
  final double lat; final double lng; final Color textColor; final Alignment alignment; final bool isInline;
  const _LocationCityItem({required this.lat, required this.lng, required this.textColor, this.alignment = Alignment.centerLeft, this.isInline = false});
  @override State<_LocationCityItem> createState() => _LocationCityItemState();
}
class _LocationCityItemState extends State<_LocationCityItem> {
  static final Map<String, String> _cache = {};
  String _city = 'Locating...';
  @override void initState() { super.initState(); _fetch(); }
  @override void didUpdateWidget(covariant _LocationCityItem old) { super.didUpdateWidget(old); if(old.lat != widget.lat || old.lng != widget.lng) _fetch(); }
  Future<void> _fetch() async {
    final key = '${widget.lat},${widget.lng}';
    if (_cache.containsKey(key)) { setState(() => _city = _cache[key]!); return; }
    if (widget.lat == 0.0 && widget.lng == 0.0) { setState(() => _city = 'Unknown'); return; }
    try {
      final res = await http.get(Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${widget.lat}&lon=${widget.lng}&zoom=18'), headers: {'User-Agent': 'AppLocker/1.0'});
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body); final a = d['address'] as Map<String, dynamic>?;
        if (a != null) {
          final parts = [
            a['village'] ?? a['suburb'] ?? a['neighbourhood'] ?? a['residential'],
            a['town'] ?? a['city'] ?? a['municipality'] ?? a['county']
          ].where((e) => e != null).cast<String>().toList();
          final c = parts.isNotEmpty ? parts.join(', ') : (d['display_name']?.split(', ')?.take(2)?.join(', ') ?? 'Unknown');
          _cache[key] = c; if(mounted) setState(() => _city = c); return;
        }
      }
    } catch (_) {}
    _cache[key] = '${widget.lat.toStringAsFixed(2)}, ${widget.lng.toStringAsFixed(2)}';
    if(mounted) setState(() => _city = _cache[key]!);
  }
  @override Widget build(BuildContext context) { 
    if (widget.isInline) return Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.my_location_rounded, size: 16, color: widget.textColor), const SizedBox(width: 4), Flexible(child: Text(_city, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: widget.textColor), maxLines: 1, overflow: TextOverflow.ellipsis))]);
    return Align(alignment: widget.alignment, child: Column(crossAxisAlignment: widget.alignment == Alignment.centerLeft ? CrossAxisAlignment.start : widget.alignment == Alignment.centerRight ? CrossAxisAlignment.end : CrossAxisAlignment.center, children: [Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.public_rounded, size: 14, color: const Color(0xFF94A3B8)), const SizedBox(width: 6), Text('Location', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))]), const SizedBox(height: 6), Text(_city, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: widget.textColor), maxLines: 2, overflow: TextOverflow.ellipsis)])); 
  }
}

class _StatusBadge extends StatelessWidget {
  final String status; const _StatusBadge({required this.status});
  @override Widget build(BuildContext context) { final bool isOnline = status == 'online'; return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: isOnline ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFFEF4444).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(status.toUpperCase(), style: GoogleFonts.outfit(color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontSize: 9, fontWeight: FontWeight.w900))); }
}

class _AppControls extends StatefulWidget {
  final bool isDark; final Color cardColor; final Color textColor; final Color borderColor;
  const _AppControls({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor});
  @override State<_AppControls> createState() => _AppControlsState();
}

class _AppControlsState extends State<_AppControls> {
  String? _selectedDeviceId;
  String _searchQuery = '';
  String _filterMode = 'all'; // all, allowed, blocked, hidden

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snapshot.data!.docs;
        if (devices.isEmpty) return const Center(child: Text('No devices paired yet.'));
        
        if (_selectedDeviceId == null && devices.isNotEmpty) {
          _selectedDeviceId = devices.first.id;
        }

        // FIXED: Replaced firstWhere orElse to avoid Web type mismatch
        final bool deviceExists = devices.any((d) => d.id == _selectedDeviceId);
        final selectedDoc = deviceExists 
            ? devices.firstWhere((d) => d.id == _selectedDeviceId)
            : devices.first;
        
        if (selectedDoc.id != _selectedDeviceId) {
           _selectedDeviceId = selectedDoc.id;
        }

        final data = selectedDoc.data() as Map<String, dynamic>;
        final apps = data['installedApps'] as List<dynamic>? ?? [];
        final blockedApps = (data['blockedApps'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        final hiddenApps = (data['hiddenApps'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        final appSchedules = data['appSchedules'] as Map<String, dynamic>? ?? {};
        // Helper: is a schedule entry currently active?
        bool isSchedActiveDesktop(Map<String, dynamic> s) {
          if (s['alwaysBlocked'] == true) return true;
          final sp = (s['start'] as String? ?? '').split(':');
          final ep = (s['end']   as String? ?? '').split(':');
          if (sp.length < 2 || ep.length < 2) return false;
          final now = TimeOfDay.now();
          final nowMin = now.hour * 60 + now.minute;
          final sMin = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
          final eMin = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
          return sMin <= eMin ? nowMin >= sMin && nowMin < eMin : nowMin >= sMin || nowMin < eMin;
        }
        // All packages blocked explicitly OR with any schedule (active or not)
        final effectivelyBlockedDesktop = <String>{
          ...blockedApps,
          ...appSchedules.keys,
        };

        // Build a lookup map from packageName -> app data for enrichment
        final installedMapDesktop = <String, Map<String, dynamic>>{};
        for (final a in apps) {
          final m = a as Map<String, dynamic>;
          final p = (m['packageName'] ?? '').toString();
          if (p.isNotEmpty) installedMapDesktop[p] = m;
        }
        final query = _searchQuery.toLowerCase();

        List<Map<String, dynamic>> filteredApps;
        if (_filterMode == 'blocked') {
          filteredApps = effectivelyBlockedDesktop.map<Map<String, dynamic>>((pkg) =>
            installedMapDesktop[pkg] ?? {'packageName': pkg, 'appName': '', 'name': '', 'label': ''}
          ).where((app) {
            final pkg = (app['packageName'] ?? '').toString();
            final name = (app['appName'] ?? app['name'] ?? app['label'] ?? pkg).toString().toLowerCase();
            final effectiveName = name.isNotEmpty ? name : pkg.toLowerCase();
            return query.isEmpty || effectiveName.contains(query) || pkg.toLowerCase().contains(query);
          }).toList();
        } else if (_filterMode == 'hidden') {
          filteredApps = hiddenApps.map<Map<String, dynamic>>((pkg) =>
            installedMapDesktop[pkg] ?? {'packageName': pkg, 'appName': '', 'name': '', 'label': ''}
          ).where((app) {
            final pkg = (app['packageName'] ?? '').toString();
            final name = (app['appName'] ?? app['name'] ?? app['label'] ?? pkg).toString().toLowerCase();
            final effectiveName = name.isNotEmpty ? name : pkg.toLowerCase();
            return query.isEmpty || effectiveName.contains(query) || pkg.toLowerCase().contains(query);
          }).toList();
        } else {
          filteredApps = apps.where((app) {
            final d = app as Map<String, dynamic>;
            final pkg = (d['packageName'] ?? '').toString();
            final name = (d['appName'] ?? d['name'] ?? d['label'] ?? '').toString().toLowerCase();
            final matchesSearch = name.contains(query) || pkg.toLowerCase().contains(query);
            if (!matchesSearch) return false;
            if (_filterMode == 'allowed') return !effectivelyBlockedDesktop.contains(pkg) && !hiddenApps.contains(pkg);
            return true; // 'all' mode
          }).cast<Map<String, dynamic>>().toList();
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
          builder: (context, userSnapshot) {
            final userData = userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
            final planId = (userData['plan'] ?? 'free').toString().toLowerCase();
            final bool isSuperAdmin = userData['role'] == 'super_admin';

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('plans').doc(planId).snapshots(),
              builder: (context, planSnapshot) {
                final planData = planSnapshot.data?.data() as Map<String, dynamic>? ?? {};
                final blockedLimit = isSuperAdmin ? 999 : (planData['blockedAppsLimit'] ?? 5);
                final hiddenLimit = isSuperAdmin ? 999 : (planData['hiddenAppsLimit'] ?? 2);

                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('App Management', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: widget.textColor)),
                          const SizedBox(height: 8),
                          Text('Monitor and restrict specific applications on child devices.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
                        ],
                      ),
                      const Spacer(),
                      if (!isSuperAdmin) 
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                             _buildMiniLimitBadge('BLOCKED', blockedApps.length, blockedLimit, const Color(0xFFEF4444)),
                             const SizedBox(height: 4),
                             _buildMiniLimitBadge('HIDDEN', hiddenApps.length, hiddenLimit, const Color(0xFF8B5CF6)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Device Selector - DROPDOWN
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF64748B).withOpacity(0.5), width: 1.5)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedDeviceId,
                        isExpanded: true,
                        dropdownColor: widget.cardColor,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6366F1)),
                        onChanged: (val) { if (val != null) setState(() => _selectedDeviceId = val); },
                        items: devices.map((doc) {
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(doc.id, style: GoogleFonts.outfit(color: widget.textColor, fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tools Row: Search + Filters
                  Row(
                    children: [
                      // Search Bar (Expanded)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF64748B).withOpacity(0.5), width: 1.5)),
                          child: TextField(
                            onChanged: (val) => setState(() => _searchQuery = val),
                            style: GoogleFonts.outfit(color: widget.textColor),
                            decoration: InputDecoration(hintText: 'Search...', hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8)), border: InputBorder.none, icon: Icon(Icons.search_rounded, color: const Color(0xFF94A3B8))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'All Apps', Icons.apps_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('allowed', 'Allowed', Icons.check_circle_outline_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('blocked', 'Blocked', Icons.block_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('hidden', 'Hidden', Icons.visibility_off_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Apps Grid
                  LayoutBuilder(builder: (context, constraints) {
                    if (apps.isEmpty) {
                      return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: Column(children: [const Icon(Icons.sync_problem_rounded, color: Color(0xFF94A3B8), size: 48), const SizedBox(height: 16), Text('No apps synced from this device yet.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 16)), Text('Ensure the child app is open on the device.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8).withOpacity(0.5), fontSize: 12))])));
                    }
                    if (filteredApps.isEmpty && _searchQuery.isNotEmpty) {
                      return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: Column(children: [const Icon(Icons.search_off_rounded, color: Color(0xFF94A3B8), size: 48), const SizedBox(height: 16), Text('No apps match "$_searchQuery"', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 16))])));
                    }
                    
                    int crossAxisCount = (constraints.maxWidth / 280).floor().clamp(1, 4);
                    return GridView.builder(
                      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 12, mainAxisSpacing: 12, mainAxisExtent: 74),
                      itemCount: filteredApps.length,
                      itemBuilder: (context, index) => _AppActionButton(
                        app: filteredApps[index] as Map<String, dynamic>, 
                        deviceId: selectedDoc.id, 
                        blockedApps: blockedApps, 
                        hiddenApps: hiddenApps, 
                        appSchedules: appSchedules, 
                        isDark: widget.isDark,
                        blockedLimit: blockedLimit,
                        hiddenLimit: hiddenLimit,
                      ),
                    );
                  }),
                ]);
              }
            );
          }
        );
      },
    );
  }

  Widget _buildFilterChip(String mode, String label, IconData icon) {
    final isSelected = _filterMode == mode;
    final color = isSelected ? const Color(0xFF6366F1) : const Color(0xFF94A3B8);
    
    return InkWell(
      onTap: () => setState(() => _filterMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF64748B).withOpacity(0.5), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.outfit(color: color, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniLimitBadge(String label, int current, int max, Color color) {
    bool isOver = current >= max;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: (isOver ? Colors.redAccent : color).withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: (isOver ? Colors.redAccent : color).withOpacity(0.2))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.w900, color: isOver ? Colors.redAccent : color, letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Text('$current/$max', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: isOver ? Colors.redAccent : widget.textColor)),
        ],
      ),
    );
  }
}

class _AppActionButton extends StatelessWidget {
  final Map<String, dynamic> app;
  final String deviceId;
  final List<String> blockedApps;
  final List<String> hiddenApps;
  final Map<String, dynamic> appSchedules;
  final bool isDark;
  final int blockedLimit;
  final int hiddenLimit;

  const _AppActionButton({
    required this.app,
    required this.deviceId,
    required this.blockedApps,
    required this.hiddenApps,
    this.appSchedules = const {},
    required this.isDark,
    required this.blockedLimit,
    required this.hiddenLimit,
  });
  void _showRestrictionDialog(BuildContext context, String pkg, String appName) {
    final schedule = appSchedules[pkg] as Map<String, dynamic>? ?? {};
    final TextEditingController startCtrl = TextEditingController(text: schedule['start'] ?? '12:00 AM');
    final TextEditingController endCtrl = TextEditingController(text: schedule['end'] ?? '12:00 PM');
    bool alwaysBlocked = schedule['alwaysBlocked'] ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.security_rounded, color: Color(0xFF6366F1)),
              const SizedBox(width: 12),
              Text('Setup Rules', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 18, color: isDark ? Colors.white : Colors.black)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(appName, style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF94A3B8))),
              const SizedBox(height: 20),
              
              // Always Blocked Card
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: alwaysBlocked ? const Color(0xFFEF4444).withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF64748B), width: 0.5)),
                child: SwitchListTile(
                  title: Text('Until I turn off', style: GoogleFonts.outfit(color: isDark ? Colors.white : Colors.black, fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('Device remains blocked 24/7', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 11)),
                  value: alwaysBlocked,
                  activeColor: const Color(0xFFEF4444),
                  onChanged: (val) => setDialogState(() => alwaysBlocked = val),
                ),
              ),
              
              if (!alwaysBlocked) ...[
                const SizedBox(height: 24),
                Text('SAFE ACCESS WINDOW', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
                const SizedBox(height: 12),
                
                // Unified Time Card (matching My Device layout)
                InkWell(
                  onTap: () async {
                    final start = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (start == null) return;
                    final end = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 23, minute: 59));
                    if (end == null) return;
                    
                    final startDt = DateTime(2022, 1, 1, start.hour, start.minute);
                    final endDt = DateTime(2022, 1, 1, end.hour, end.minute);
                    
                    setDialogState(() {
                      startCtrl.text = DateFormat('h:mm a', 'en_US').format(startDt);
                      endCtrl.text = DateFormat('h:mm a', 'en_US').format(endDt);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF64748B), width: 0.5)),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded, color: Color(0xFF6366F1), size: 20),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Usable Time Window', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8))),
                              const SizedBox(height: 2),
                              Text('${startCtrl.text} - ${endCtrl.text}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black)),
                            ],
                          ),
                        ),
                        const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF94A3B8)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('App will be blocked outside this window.', style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 11, fontStyle: FontStyle.italic)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold))
            ),
            ElevatedButton(
            onPressed: () async {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) {
                  final allowed = await PlanGate.requireForUser(
                    context, uid, (f) => f.appRestrictions,
                    featureLabel: 'App Restrictions',
                  );
                  if (!allowed) { Navigator.pop(context); return; }
                  // Schedule-window restrictions also need scheduleLock
                  if (!alwaysBlocked) {
                    final canSchedule = await PlanGate.requireForUser(
                      context, uid, (f) => f.scheduleLock,
                      featureLabel: 'Scheduled App Restrictions',
                    );
                    if (!canSchedule) { Navigator.pop(context); return; }
                  }
                }
                if (!blockedApps.contains(pkg) && blockedApps.length >= blockedLimit) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Purchase a higher plan to block more than $blockedLimit apps.'), backgroundColor: Colors.redAccent));
                  Navigator.pop(context);
                  return;
                }

                final newSchedules = Map<String, dynamic>.from(appSchedules);
                newSchedules[pkg] = {
                  'start': startCtrl.text,
                  'end': endCtrl.text,
                  'alwaysBlocked': alwaysBlocked,
                };
                
                final newBlocked = List<String>.from(blockedApps);
                if (!newBlocked.contains(pkg)) newBlocked.add(pkg);

                FirebaseFirestore.instance.collection('devices').doc(deviceId).update({
                  'appSchedules': newSchedules,
                  'blockedApps': newBlocked,
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
              ),
              child: Text('Save Rule', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final String pkg = (app['packageName'] ?? '').toString();
    final String appName = app['appName'] ?? app['name'] ?? app['label'] ?? 'Unknown App';
    final bool isBlocked = blockedApps.contains(pkg);
    final bool isHidden = hiddenApps.contains(pkg);
    final schedule = appSchedules[pkg] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF64748B).withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        children: [
          app['iconBase64'] != null 
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(base64Decode(app['iconBase64']), width: 28, height: 28, fit: BoxFit.cover)
              )
            : Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(appName.isNotEmpty ? appName[0].toUpperCase() : 'A', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF6366F1), fontSize: 16)),
                )
              ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(appName, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13, color: isDark ? Colors.white : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (isBlocked && schedule != null)
                  Text(schedule['alwaysBlocked'] ?? true ? 'Until Turned Off' : '${schedule['start']} - ${schedule['end']}', style: GoogleFonts.outfit(fontSize: 9, color: const Color(0xFF6366F1), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 18),
            color: isDark ? const Color(0xFF0F1A35) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: EdgeInsets.zero,
            onSelected: (action) async {
              if (action == 'schedule_block') {
                _showRestrictionDialog(context, pkg, appName);
                return;
              }
              final newBlocked = List<String>.from(blockedApps)..remove(pkg);
              final newHidden  = List<String>.from(hiddenApps)..remove(pkg);
              final newSchedules = Map<String, dynamic>.from(appSchedules);
              if (action == 'block_now') {
                if (blockedApps.length >= blockedLimit) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Blocked apps limit reached ($blockedLimit)'), backgroundColor: Colors.redAccent));
                  return;
                }
                newBlocked.add(pkg);
              } else if (action == 'hide') {
                if (hiddenApps.length >= hiddenLimit) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hidden apps limit reached ($hiddenLimit)'), backgroundColor: Colors.redAccent));
                  return;
                }
                newHidden.add(pkg);
              } else if (action == 'allow') {
                newSchedules.remove(pkg);
              }
              FirebaseFirestore.instance.collection('devices').doc(deviceId).update({
                'blockedApps': newBlocked, 'hiddenApps': newHidden, 'appSchedules': newSchedules,
              });
            },
            itemBuilder: (c) {
              final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
              return [
                PopupMenuItem(value: 'allow', child: Row(children: [const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 16), const SizedBox(width: 8), Text('Allow', style: GoogleFonts.outfit(fontSize: 13, color: textColor))])),
                PopupMenuItem(value: 'block_now', child: Row(children: [const Icon(Icons.block_rounded, color: Color(0xFFEF4444), size: 16), const SizedBox(width: 8), Text('Block instantly', style: GoogleFonts.outfit(fontSize: 13, color: textColor))])),
                PopupMenuItem(value: 'hide', child: Row(children: [const Icon(Icons.visibility_off_rounded, color: Color(0xFFFBBF24), size: 16), const SizedBox(width: 8), Text('Hide', style: GoogleFonts.outfit(fontSize: 13, color: textColor))])),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'schedule_block', child: Row(children: [const Icon(Icons.schedule_rounded, color: Color(0xFF6366F1), size: 16), const SizedBox(width: 8), Text('Schedule Block', style: GoogleFonts.outfit(fontSize: 13, color: textColor, fontWeight: FontWeight.w700))])),
              ];
            },
          ),
        ],
      ),
    );
  }
}

class _SchedulesView extends StatefulWidget {
  final bool isDark; 
  final Color cardColor; 
  final Color textColor; 
  final Color borderColor;

  const _SchedulesView({
    required this.isDark, 
    required this.cardColor, 
    required this.textColor, 
    required this.borderColor
  });

  @override
  State<_SchedulesView> createState() => _SchedulesViewState();
}

class _SchedulesViewState extends State<_SchedulesView> {
  String _to12h(String t) {
    if (t.toUpperCase().contains('AM') || t.toUpperCase().contains('PM')) return t;
    final parts = t.split(':');
    if (parts.length < 2) return t;
    int h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final p = h < 12 ? 'AM' : 'PM';
    h = h % 12; if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')} $p';
  }

  void _editRule(BuildContext context, Map<String, dynamic> rule) async {
    final deviceId = rule['deviceId'] as String;
    final isDeviceLock = rule['type'] == 'Device Lock';
    final rawRule = rule['rawRule'] as String? ?? rule['rule'] as String? ?? '';

    if (isDeviceLock) {
      final rawStart = rule['rawStart'] as String? ?? '';
      final rawEnd   = rule['rawEnd']   as String? ?? '';
      final sp = rawStart.split(':');
      final ep = rawEnd.split(':');
      TimeOfDay startTime = sp.length >= 2 ? TimeOfDay(hour: int.tryParse(sp[0]) ?? 22, minute: int.tryParse(sp[1]) ?? 0) : const TimeOfDay(hour: 22, minute: 0);
      TimeOfDay endTime   = ep.length >= 2 ? TimeOfDay(hour: int.tryParse(ep[0]) ?? 6,  minute: int.tryParse(ep[1]) ?? 0) : const TimeOfDay(hour: 6,  minute: 0);

      final newStart = await showTimePicker(context: context, initialTime: startTime, helpText: 'Select Lock Start Time');
      if (newStart == null || !context.mounted) return;
      final newEnd = await showTimePicker(context: context, initialTime: endTime, helpText: 'Select Lock End Time');
      if (newEnd == null || !context.mounted) return;

      String fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

      final doc = await FirebaseFirestore.instance.collection('devices').doc(deviceId).get();
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;
      final list = List<Map<String, dynamic>>.from(
        (data['lockSchedules'] ?? []).map((s) => Map<String, dynamic>.from(s))
      );
      // Find and replace the matching rule using raw 24h values
      final idx = list.indexWhere((s) => s['start'] == rawStart && s['end'] == rawEnd);
      if (idx != -1) {
        list[idx] = {'start': fmt(newStart), 'end': fmt(newEnd)};
      } else {
        list.add({'start': fmt(newStart), 'end': fmt(newEnd)});
      }
      await FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'lockSchedules': list});
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schedule updated.'), backgroundColor: Color(0xFF10B981)));
    } else {
      // App Restriction edit
      final pkg = rule['pkgName'] as String? ?? '';
      final target = rule['target'] as String? ?? pkg;
      bool alwaysBlocked = rawRule == 'Always Blocked';
      final rawStart = rule['rawStart'] as String? ?? '';
      final rawEnd   = rule['rawEnd']   as String? ?? '';
      final startCtrl = TextEditingController(text: alwaysBlocked ? '12:00 AM' : _to12h(rawStart));
      final endCtrl = TextEditingController(text: alwaysBlocked ? '12:00 PM' : _to12h(rawEnd));

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor: widget.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Edit App Rule', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: widget.textColor)),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(target, style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8))),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text('Always Restricted', style: GoogleFonts.outfit(color: widget.textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text('Restrict 24/7', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 11)),
                value: alwaysBlocked,
                activeColor: const Color(0xFFEF4444),
                onChanged: (v) => setS(() => alwaysBlocked = v),
              ),
              if (!alwaysBlocked) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final s = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                    if (s == null) return;
                    final e = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 23, minute: 59));
                    if (e == null) return;
                    final startDt = DateTime(2022, 1, 1, s.hour, s.minute);
                    final endDt = DateTime(2022, 1, 1, e.hour, e.minute);
                    setS(() {
                      startCtrl.text = DateFormat('h:mm a', 'en_US').format(startDt);
                      endCtrl.text = DateFormat('h:mm a', 'en_US').format(endDt);
                    });
                  },
                  child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF64748B), width: 0.5)),
                    child: Row(children: [const Icon(Icons.access_time_rounded, color: Color(0xFF6366F1), size: 18), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Time Window', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8))), Text('${startCtrl.text} - ${endCtrl.text}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: widget.textColor))])), const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF94A3B8))])),
                  ),
              ],
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final doc = await FirebaseFirestore.instance.collection('devices').doc(deviceId).get();
                  if (!doc.exists) return;
                  final data = doc.data() as Map<String, dynamic>;
                  final schedules = Map<String, dynamic>.from(data['appSchedules'] ?? {});
                  schedules[pkg] = {'start': startCtrl.text, 'end': endCtrl.text, 'alwaysBlocked': alwaysBlocked};
                  await FirebaseFirestore.instance.collection('devices').doc(deviceId).update({'appSchedules': schedules});
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('App rule updated.'), backgroundColor: Color(0xFF10B981)));
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override 
  Widget build(BuildContext context) { 
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snapshot.data!.docs;
        
        final List<Map<String, dynamic>> allRules = [];
        for (var doc in devices) {
          final data = doc.data() as Map<String, dynamic>;
          final deviceId = doc.id;
          
          // Device Lock Schedules
          final lockSchedules = data['lockSchedules'] as List<dynamic>? ?? [];
          for (var s in lockSchedules) {
            final rawS = s['start'] as String? ?? '';
            final rawE = s['end']   as String? ?? '';
            allRules.add({
              'deviceId': deviceId,
              'type': 'Device Lock',
              'rule': '${_to12h(rawS)} – ${_to12h(rawE)}',
              'rawRule': '$rawS - $rawE',
              'rawStart': rawS,
              'rawEnd':   rawE,
              'target': 'Full Device',
              'icon': Icons.smartphone_rounded,
              'color': const Color(0xFFEC4899),
            });
          }
          
          // App Schedules
          final appSchedules = data['appSchedules'] as Map<String, dynamic>? ?? {};
          appSchedules.forEach((pkg, schedule) {
            final s = schedule as Map<String, dynamic>;
            final always = s['alwaysBlocked'] ?? false;
            final rawS = s['start'] as String? ?? '';
            final rawE = s['end']   as String? ?? '';
            allRules.add({
              'deviceId': deviceId,
              'type': 'App Restriction',
              'rule': always ? 'Always Blocked' : '${_to12h(rawS)} – ${_to12h(rawE)}',
              'rawRule': always ? 'Always Blocked' : '$rawS - $rawE',
              'rawStart': rawS,
              'rawEnd':   rawE,
              'target': pkg.split('.').last.toUpperCase(),
              'pkgName': pkg,
              'icon': Icons.apps_rounded,
              'color': const Color(0xFF6366F1),
            });
          });
        }

        if (allRules.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const HeroIcon(HeroIcons.calendar, size: 64, color: Color(0xFFCBD5E1)), 
                const SizedBox(height: 16), 
                Text('No active rules found', style: GoogleFonts.outfit(fontSize: 18, color: widget.textColor))
              ]
            )
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active Time Rules', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: widget.textColor)),
            const SizedBox(height: 8),
            Text('Centralized overview of all device and app restrictions.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
            const SizedBox(height: 32),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allRules.length,
              itemBuilder: (context, index) {
                final rule = allRules[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: widget.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF64748B), width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: (rule['color'] as Color).withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(rule['icon'] as IconData, color: rule['color'] as Color, size: 24),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(rule['type'], style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: rule['color'] as Color, letterSpacing: 1.2)),
                                const Spacer(),
                                Text(rule['deviceId'], style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8))),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(rule['target'], style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: widget.textColor)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time_filled_rounded, size: 14, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 6),
                                Text(rule['rule'], style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF64748B), fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        onPressed: () {
                          if (rule['type'] == 'Device Lock') {
                            final rawStart = rule['rawStart'] as String? ?? '';
                            final rawEnd   = rule['rawEnd']   as String? ?? '';
                            FirebaseFirestore.instance.collection('devices').doc(rule['deviceId']).get().then((doc) {
                              if (!doc.exists) return;
                              final data = doc.data() as Map<String, dynamic>;
                              final list = List<Map<String, dynamic>>.from(data['lockSchedules'] ?? []);
                              list.removeWhere((s) => s['start'] == rawStart && s['end'] == rawEnd);
                              FirebaseFirestore.instance.collection('devices').doc(rule['deviceId']).update({'lockSchedules': list});
                            });
                          } else {
                            FirebaseFirestore.instance.collection('devices').doc(rule['deviceId']).get().then((doc) {
                              if (!doc.exists) return;
                              final data = doc.data() as Map<String, dynamic>;
                              final schedules = Map<String, dynamic>.from(data['appSchedules'] ?? {});
                              final pkg = rule['pkgName'] as String;
                              schedules.remove(pkg);
                              FirebaseFirestore.instance.collection('devices').doc(rule['deviceId']).update({'appSchedules': schedules});
                            });
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                      ),
                      IconButton(
                        onPressed: () => _editRule(context, rule),
                        icon: const Icon(Icons.edit_note_rounded, size: 22, color: Color(0xFF6366F1)),
                        tooltip: 'Edit Rule',
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      }
    );
  }
}

class _LocationView extends StatelessWidget {
  final bool isDark; 
  final Color textColor;
  final VoidCallback? onBack;
  const _LocationView({required this.isDark, required this.textColor, this.onBack});

  @override 
  Widget build(BuildContext context) { 
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snapshot.data!.docs;
        
        final List<Marker> markers = [];
        LatLng? center;
        
        for (var doc in devices) {
          final data = doc.data() as Map<String, dynamic>;
          final lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
          final lng = (data['lng'] as num?)?.toDouble() ?? 0.0;
          final isOnline = data['status'] == 'online';
          
          if (lat != 0.0 || lng != 0.0) {
            center ??= LatLng(lat, lng);
            markers.add(
              Marker(
                point: LatLng(lat, lng),
                width: 80,
                height: 80,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white, 
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))]
                      ),
                      child: Text(
                        doc.id.length > 10 ? '${doc.id.substring(0, 8)}...' : doc.id, 
                        style: GoogleFonts.outfit(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 10, fontWeight: FontWeight.bold)
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.location_on_rounded, color: Colors.red, size: 36),
                  ],
                ),
              ),
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Global Positioning', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
                    const SizedBox(height: 4),
                    Text('Tracking ${markers.length} active device locations', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF6366F1)),
                      const SizedBox(width: 8),
                      Text('LIVE SYNC', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF6366F1), letterSpacing: 1)),
                    ],
                  ),
                ),
                if (onBack != null) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF6366F1)),
                    tooltip: 'Go Back',
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF6366F1).withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),
            Container(
              height: 640, 
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32), 
                border: Border.all(color: const Color(0xFF64748B), width: 0.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))]
              ), 
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32), 
                child: FlutterMap(
                  options: MapOptions(initialCenter: center ?? const LatLng(0,0), initialZoom: center != null ? 12 : 2), 
                  children: [
                    TileLayer(
                      urlTemplate: isDark 
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    MarkerLayer(markers: markers),
                  ]
                )
              )
            ),
          ],
        );
      }
    );
  }
}

class _ReportsView extends StatelessWidget {
  final bool isDark; final Color cardColor; final Color textColor; final Color borderColor;
  const _ReportsView({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor});
  
  @override 
  Widget build(BuildContext context) { 
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final devices = snapshot.data!.docs;
        
        double totalScreenTimeHours = 0;
        int totalBlocked = 0;
        int activeDevices = 0;
        
        List<Map<String, dynamic>> deviceEvents = [];
        Map<String, int> appUsageMap = {};
        
        for (var doc in devices) {
          final data = doc.data() as Map<String, dynamic>;
          final String deviceId = doc.id;
          
          if (data['status'] == 'online') activeDevices++;
          
          final blockedApps = data['blockedApps'] as List<dynamic>? ?? [];
          totalBlocked += blockedApps.length;
          
          final usageStats = data['usageStats'] as Map<dynamic, dynamic>? ?? {};
          usageStats.forEach((key, value) {
             if (value is num) {
                 totalScreenTimeHours += (value / (1000 * 60 * 60));
                 appUsageMap[key.toString()] = (appUsageMap[key.toString()] ?? 0) + value.toInt();
             }
          });
          
          if (data['locked'] == true) {
             deviceEvents.add({'title': 'Manual lock active', 'device': deviceId, 'icon': Icons.lock_rounded, 'color': const Color(0xFF6366F1), 'time': 'Now'});
          }
          if ((data['battery'] ?? 100) < 20) {
             deviceEvents.add({'title': 'Battery critical low', 'device': deviceId, 'icon': Icons.battery_alert_rounded, 'color': const Color(0xFFEF4444), 'time': 'Now'});
          }
          if (data['status'] == 'online') {
             deviceEvents.add({'title': 'Device is online', 'device': deviceId, 'icon': Icons.cell_tower_rounded, 'color': const Color(0xFF10B981), 'time': 'Recent'});
          }
        }
        
        var sortedApps = appUsageMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        var topApps = sortedApps.take(5).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity Reports', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
            const SizedBox(height: 8),
            Text('Live insights into usage patterns and security events.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
            const SizedBox(height: 32),
            
            // Overview Stats
            Row(
              children: [
                Expanded(child: _buildReportCard('Total Screen Time', '${totalScreenTimeHours.toStringAsFixed(1)}h', 'LIVE', const Color(0xFF6366F1))),
                const SizedBox(width: 16),
                Expanded(child: _buildReportCard('Blocked Threats', '$totalBlocked', 'LIVE', const Color(0xFFEF4444))),
                const SizedBox(width: 16),
                Expanded(child: _buildReportCard('Active Devices', '$activeDevices', 'LIVE', const Color(0xFF10B981))),
              ],
            ),
            
            const SizedBox(height: 32),
            
            if (topApps.isNotEmpty) ...[
               Container(
                 padding: const EdgeInsets.all(24),
                 decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor, width: 0.5)),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                      Text('Top Monitored Applications (Usage)', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                      const SizedBox(height: 16),
                      ...topApps.map((e) {
                         double mins = e.value / (1000 * 60);
                         return Padding(
                           padding: const EdgeInsets.only(bottom: 12),
                           child: Row(
                             children: [
                                const Icon(Icons.android_rounded, color: Color(0xFF10B981), size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text(e.key, style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.bold))),
                                Text('${mins.toStringAsFixed(1)} min', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
                             ]
                           )
                         );
                      }).toList(),
                   ]
                 )
               ),
               const SizedBox(height: 32),
            ],
            
            Text('Real-Time Status Alerts', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 16),
            
            if (deviceEvents.isEmpty) 
               Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('No active events.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))))),
               
            ...deviceEvents.map((evt) => _buildEventItem(evt['title'], evt['device'], evt['time'], evt['icon'], evt['color'])).toList(),
          ],
        );
      }
    );
  }

  Widget _buildReportCard(String title, String value, String trend, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF64748B), width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(value, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
              const Spacer(),
              if (trend.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(trend, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventItem(String title, String device, String time, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF64748B), width: 0.5)),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)), Text('$device • $time', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)))])),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }
}

class _SettingsView extends StatefulWidget {
  final bool isDark; 
  final Color cardColor; 
  final Color textColor; 
  final Color borderColor;
  const _SettingsView({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor});

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  String? _selectedDeviceId;
  final TextEditingController _taskTitleCtrl = TextEditingController();
  final TextEditingController _taskListCtrl = TextEditingController();
  final TextEditingController _warningTitleCtrl = TextEditingController();
  final TextEditingController _warningListCtrl = TextEditingController();
  final TextEditingController _lockHeadlineCtrl = TextEditingController();
  final TextEditingController _restHeadlineCtrl = TextEditingController();
  final TextEditingController _lockMsgCtrl = TextEditingController();
  final TextEditingController _restMsgCtrl = TextEditingController();
  final TextEditingController _parentQuoteCtrl = TextEditingController();
  final TextEditingController _profileImageUrlCtrl = TextEditingController();
  final TextEditingController _unlockGreetingCtrl = TextEditingController();
  bool _isLoading = false;
  bool _uploadingImage = false;
  bool _settingsInitialized = false;

  @override
  void initState() {
    super.initState();
    for (var c in [_profileImageUrlCtrl, _lockHeadlineCtrl, _taskTitleCtrl, _taskListCtrl, _restHeadlineCtrl, _restMsgCtrl, _warningListCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  Future<void> _pickAndUploadImage() async {
    if (_selectedDeviceId == null) return;
    final uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    uploadInput.click();
    await uploadInput.onChange.first;
    final file = uploadInput.files?.first;
    if (file == null) return;

    setState(() => _uploadingImage = true);
    try {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      final bytes = reader.result as List<int>;
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images/$uid/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      final metadata = SettableMetadata(contentType: file.type);
      await ref.putData(Uint8List.fromList(bytes), metadata);
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() => _profileImageUrlCtrl.text = url);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image uploaded! Tap "Save All Settings" to apply.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  void _saveSettings() async {
    if (_selectedDeviceId == null) return;
    setState(() => _isLoading = true);
    
    // Check subscription
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).get();
    final userData = userDoc.data() as Map<String, dynamic>? ?? {};
    final String plan = userData['plan'] ?? 'free';
    final DateTime? expiry = (userData['expiryDate'] as Timestamp?)?.toDate();
    final bool isExpired = expiry != null && expiry.isBefore(DateTime.now());

    if (isExpired && plan != 'free') {
       setState(() => _isLoading = false);
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscription expired. Settings are currently paused.'), backgroundColor: Colors.redAccent));
       }
       return;
    }
    final List<String> taskList = _taskListCtrl.text.split('\n').where((s) => s.trim().isNotEmpty).toList();
    final List<String> warningList = _warningListCtrl.text.split('\n').where((s) => s.trim().isNotEmpty).toList();

    try {
      await FirebaseFirestore.instance.collection('devices').doc(_selectedDeviceId).update({
        'taskTitle': _taskTitleCtrl.text.trim(),
        'taskList': taskList,
        'warningTitle': _warningTitleCtrl.text.trim(),
        'warningList': warningList,
        'lockHeadline': _lockHeadlineCtrl.text.trim(),
        'restrictedHeadline': _restHeadlineCtrl.text.trim(),
        'lockMessage': _lockMsgCtrl.text.trim(),
        'restrictedMessage': _restMsgCtrl.text.trim(),
        'parentQuote': _parentQuoteCtrl.text.trim(),
        'profileImageUrl': _profileImageUrlCtrl.text.trim(),
        'unlockGreeting': _unlockGreetingCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customization settings saved successfully!'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadDeviceSettings(String deviceId, List<QueryDocumentSnapshot> devices) {
    try {
      final doc = devices.firstWhere((d) => d.id == deviceId);
      final data = doc.data() as Map<String, dynamic>;
      _taskTitleCtrl.text = data['taskTitle'] ?? data['lockTitle'] ?? 'Mother\'s To-Do List';
      _taskListCtrl.text = (data['taskList'] as List? ?? data['todos'] as List? ?? []).join('\n');
      _warningTitleCtrl.text = data['warningTitle'] ?? 'Restricted Access';
      _warningListCtrl.text = (data['warningList'] as List? ?? []).join('\n');
      _lockHeadlineCtrl.text = data['lockHeadline'] ?? 'LOCKED';
      _restHeadlineCtrl.text = data['restrictedHeadline'] ?? 'APP RESTRICTED';
      _lockMsgCtrl.text = data['lockMessage'] ?? 'This device is locked by your parent.\nPlease complete your routines to unlock.';
      _restMsgCtrl.text = data['restrictedMessage'] ?? 'Access to this application is restricted by parent settings.';
      _parentQuoteCtrl.text = data['parentQuote'] ?? '';
      _profileImageUrlCtrl.text = data['profileImageUrl'] ?? '';
      _unlockGreetingCtrl.text = data['unlockGreeting'] ?? 'Enjoy Your Day';
    } catch (e) {
      debugPrint('Error loading device settings: $e');
    }
  }

  @override
  void dispose() {
    _taskTitleCtrl.dispose();
    _taskListCtrl.dispose();
    _warningTitleCtrl.dispose();
    _warningListCtrl.dispose();
    _lockHeadlineCtrl.dispose();
    _restHeadlineCtrl.dispose();
    _lockMsgCtrl.dispose();
    _restMsgCtrl.dispose();
    _parentQuoteCtrl.dispose();
    _profileImageUrlCtrl.dispose();
    _unlockGreetingCtrl.dispose();
    super.dispose();
  }

  @override 
  Widget build(BuildContext context) { 
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        final devices = snapshot.data?.docs ?? [];
        if (!_settingsInitialized && devices.isNotEmpty) {
          _settingsInitialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedDeviceId = devices.first.id);
              _loadDeviceSettings(devices.first.id, devices);
            }
          });
        }

        final sectionBg = widget.isDark ? const Color(0xFF091526) : const Color(0xFFECFDF5);
        final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
        final lockTasks = _taskListCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
        final rTasks = _warningListCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Settings', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: widget.textColor)),
            const SizedBox(height: 8),
            Text('Manage your account, preferences, and system security.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
            const SizedBox(height: 32),

            // ── Child App View Data ──
            Row(children: [
              Text('Child App View Data', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: textColor)),
              const Spacer(),
              GestureDetector(
                onTap: _isLoading ? null : _saveSettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                  decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(20)),
                  child: Text(_isLoading ? '...' : 'save', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: sectionBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _desktopTf('Paste your URL here', _profileImageUrlCtrl, hint: 'https://example.com/photo.jpg'),
                  _desktopTf('Parent Quote', _parentQuoteCtrl, maxLines: 3, hint: '"I love you more than words can ever say.\nMama missed you so much"'),
                  _desktopTf('Unlock Greetings', _unlockGreetingCtrl, hint: '" Enjoy Your Day My Child. "'),
                ])),
                const SizedBox(width: 16),
                Column(children: [
                  Container(
                    width: 100, height: 130,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: widget.isDark ? Colors.white10 : const Color(0xFFE2E8F0)), clipBehavior: Clip.hardEdge,
                    child: _profileImageUrlCtrl.text.isNotEmpty
                        ? Image.network(_profileImageUrlCtrl.text, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 40, color: Color(0xFF94A3B8)))
                        : const Icon(Icons.person_rounded, size: 40, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _uploadingImage ? null : _pickAndUploadImage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: const Color(0xFFFBBF24), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _uploadingImage ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_rounded, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(_uploadingImage ? '...' : 'Choose Img', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () {
                      final imgUrl = _profileImageUrlCtrl.text;
                      final quote = _parentQuoteCtrl.text;
                      final greeting = _unlockGreetingCtrl.text;
                      showDialog(context: context, builder: (ctx) => Dialog(
                        backgroundColor: Colors.transparent,
                        child: SingleChildScrollView(
                          child: Container(
                            width: 400,
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 32, offset: const Offset(0, 8))]),
                            padding: const EdgeInsets.all(24),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              // App header
                              Row(children: [
                                Text('AppLocker', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B))),
                                const SizedBox(width: 8),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(20)), child: Text('v2.0.0+12', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                                const Spacer(),
                                const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8), size: 26),
                                const SizedBox(width: 16),
                                const Icon(Icons.logout_rounded, color: Color(0xFF94A3B8), size: 26),
                              ]),
                              const SizedBox(height: 16),
                              // Status card
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                decoration: BoxDecoration(color: const Color(0xFFEEEFF8), borderRadius: BorderRadius.circular(16)),
                                child: Row(children: [
                                  Container(width: 38, height: 38, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 24)),
                                  const SizedBox(width: 12),
                                  Text('Online', style: GoogleFonts.outfit(fontSize: 16, color: const Color(0xFF374151))),
                                  const Spacer(),
                                  const Icon(Icons.battery_full_rounded, color: Color(0xFF22C55E), size: 32),
                                  const SizedBox(width: 6),
                                  Text('100%', style: GoogleFonts.outfit(fontSize: 16, color: const Color(0xFF374151))),
                                ]),
                              ),
                              const SizedBox(height: 14),
                              // Quote + photo card
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(color: const Color(0xFFEEEFF8), borderRadius: BorderRadius.circular(16)),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    const Text('♥ ~', style: TextStyle(fontSize: 24, color: Color(0xFFEF4444))),
                                    const SizedBox(height: 10),
                                    Text(
                                      quote.isNotEmpty ? '"$quote"' : '"You are my heart in human form. No matter where life takes you, you will always be my greatest love."',
                                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B), height: 1.5),
                                    ),
                                  ])),
                                  const SizedBox(width: 14),
                                  Container(
                                    width: 120, height: 155,
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF22C55E), width: 2.5)),
                                    clipBehavior: Clip.hardEdge,
                                    child: imgUrl.isNotEmpty
                                      ? Image.network(imgUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 50, color: Color(0xFF94A3B8)))
                                      : const Icon(Icons.person_rounded, size: 50, color: Color(0xFF94A3B8)),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 14),
                              // Device Unlocked card
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
                                decoration: BoxDecoration(color: const Color(0xFFEEEFF8), borderRadius: BorderRadius.circular(16)),
                                child: Row(children: [
                                  Container(width: 60, height: 60, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.lock_open_rounded, color: Color(0xFF22C55E), size: 34)),
                                  const SizedBox(width: 18),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('Device Unlocked', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B))),
                                    Text('"${greeting.isNotEmpty ? greeting : 'Enjoy Your Day'}"', style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF374151))),
                                  ])),
                                ]),
                              ),
                              const SizedBox(height: 18),
                              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: GoogleFonts.outfit(color: const Color(0xFF22C55E), fontWeight: FontWeight.w700))),
                            ]),
                          ),
                        ),
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(8)),
                      child: Text('Preview', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 24),

            // ── Device Lock Screen Settings ──
            Text('Device Lock Screen Settings', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: textColor)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: sectionBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Target Device', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: widget.isDark ? const Color(0xFF0F1A35) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.8))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedDeviceId,
                        isExpanded: true,
                        dropdownColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                        style: GoogleFonts.outfit(fontSize: 13, color: textColor),
                        items: devices.map((d) => DropdownMenuItem(value: d.id, child: Text(d.id))).toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => _selectedDeviceId = val);
                          _loadDeviceSettings(val, devices);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Text('Lock Screen Heading', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('Core Messaging', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: textColor)),
                  ]),
                  const SizedBox(height: 4),
                  _desktopTfRaw(_lockHeadlineCtrl, hint: 'LOCKED'),
                  _desktopTf('Lock Screen Title', _taskTitleCtrl, hint: 'Parent Tasks'),
                  _desktopTf('Lock Screen Task  (One per line )', _taskListCtrl, maxLines: 4, hint: 'Cook Food\nBreakfast\nWash Dishes\nClean House'),
                ])),
                const SizedBox(width: 16),
                Column(children: [
                  _desktopLockPhoneMockup(
                    heading: _lockHeadlineCtrl.text.isEmpty ? 'LOCKED' : _lockHeadlineCtrl.text,
                    title: _taskTitleCtrl.text.isEmpty ? 'YOUR TASKS' : _taskTitleCtrl.text.toUpperCase(),
                    tasks: lockTasks.isEmpty ? ['Cook Food 11:00AM', 'Lunch 12:00 AM', 'Wash Dishes 12:30 PM'] : lockTasks,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _desktopShowLockPreview(textColor),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                      decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(10)),
                      child: Text('Preview', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 24),

            // ── App Restricted Settings ──
            Row(children: [
              Text('App Restricted Settings', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: textColor)),
              const Spacer(),
              GestureDetector(
                onTap: _isLoading ? null : _saveSettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                  decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(20)),
                  child: Text(_isLoading ? '...' : 'save', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: sectionBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('App Restricted Headline', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('Core Messaging', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: textColor)),
                  ]),
                  const SizedBox(height: 4),
                  _desktopTfRaw(_restHeadlineCtrl, hint: 'APP RESTRICTED'),
                  _desktopTf('App Restricted Fallback Message', _restMsgCtrl, maxLines: 2, hint: 'Access to this application is restricted by parent settings.'),
                  Row(children: [
                    Expanded(child: Text('List of Task to Show  (one per line)', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600))),
                    const SizedBox(width: 4),
                    Text('Restricted Task List', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: textColor)),
                  ]),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _warningListCtrl,
                    maxLines: 5,
                    style: GoogleFonts.outfit(fontSize: 13, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Cook Food\nBreakfast\nWash Dishes\nClean House',
                      hintStyle: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                      filled: true, fillColor: widget.isDark ? const Color(0xFF0F1A35) : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ])),
                const SizedBox(width: 16),
                Column(children: [
                  _desktopRestrictedPhoneMockup(
                    headline: _restHeadlineCtrl.text.isEmpty ? 'RESTRICTED' : _restHeadlineCtrl.text,
                    tasks: rTasks.isEmpty ? ['Cook Food 11:00AM', 'Lunch 12:00 AM'] : rTasks,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _desktopShowRestrictedPreview(textColor),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                      decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(10)),
                      child: Text('Preview', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ]),
              ]),
            ),

            const SizedBox(height: 32),

            _buildSettingsSection('ACCOUNT PROFILE', [
              _buildSettingTile('Avatar & Handle', 'Update your personality and username', Icons.person_outline_rounded),
              _buildSettingTile('Email Address', 'parent.admin@example.com', Icons.alternate_email_rounded),
              _buildSettingTile('Subscription Plan', 'Premium Professional', Icons.workspace_premium_rounded, trailing: 'UPGRADE'),
            ]),
            
            const SizedBox(height: 32),
            
            _buildSettingsSection('PRIVACY & SECURITY', [
              _buildSettingTile('Change Password', 'Last updated 3 months ago', Icons.lock_outline_rounded),
              _buildSettingTile('Two-Factor Auth', 'Enabled for enhanced security', Icons.verified_user_outlined, isSuccess: true),
              _buildSettingTile('Connected Devices', 'Manage all paired child applications', Icons.devices_rounded),
            ]),
            
            const SizedBox(height: 32),
            
            _buildSettingsSection('NOTIFICATIONS', [
              _buildSettingTile('Security Alerts', 'Instant push notifications for violations', Icons.notifications_active_outlined, hasSwitch: true, switchValue: true),
              _buildSettingTile('Location Updates', 'Receive alerts when boundaries are crossed', Icons.my_location_rounded, hasSwitch: true, switchValue: true),
              _buildSettingTile('Weekly Reports', 'Digest of child usage and activity', Icons.summarize_outlined, hasSwitch: true, switchValue: false),
            ]),
            
            const SizedBox(height: 48),
            Center(
              child: TextButton(
                onPressed: () {}, 
                child: Text('LOGOUT ACCOUNT', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFFEF4444), letterSpacing: 2))
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _desktopTf(String label, TextEditingController ctrl, {int maxLines = 1, String? hint}) {
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final bg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(controller: ctrl, maxLines: maxLines, style: GoogleFonts.outfit(fontSize: 13, color: textColor),
        decoration: InputDecoration(hintText: hint, hintStyle: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)), filled: true, fillColor: bg, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: border, enabledBorder: border, focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.5)))),
      const SizedBox(height: 10),
    ]);
  }

  Widget _desktopTfRaw(TextEditingController ctrl, {String? hint}) {
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final bg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 0.8));
    return Column(children: [
      TextField(controller: ctrl, style: GoogleFonts.outfit(fontSize: 13, color: textColor),
        decoration: InputDecoration(hintText: hint, hintStyle: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)), filled: true, fillColor: bg, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: border, enabledBorder: border, focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.5)))),
      const SizedBox(height: 10),
    ]);
  }

  Widget _desktopLockPhoneMockup({required String heading, required String title, required List<String> tasks}) {
    return Container(
      width: 130, height: 250,
      decoration: BoxDecoration(color: const Color(0xFFFBBF24), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF1E293B), width: 3.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))]),
      child: ClipRRect(borderRadius: BorderRadius.circular(17), child: Column(children: [
        Container(height: 12, color: const Color(0xFF1E293B), child: Center(child: Container(width: 34, height: 5, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(3))))),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Column(children: [
          Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1E293B), width: 2)), child: const Icon(Icons.add, size: 14, color: Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text(heading, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B), letterSpacing: 1), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Container(width: double.infinity, padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.65), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.outfit(fontSize: 7, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
              const SizedBox(height: 3),
              ...tasks.take(3).map((t) => Text(t, style: GoogleFonts.outfit(fontSize: 6, color: const Color(0xFF374151)), overflow: TextOverflow.ellipsis)),
            ])),
          const SizedBox(height: 8),
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 5), decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(8)),
            child: Text('SEND MESSAGE HERE', style: GoogleFonts.outfit(fontSize: 6, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.center)),
          const SizedBox(height: 5),
          Text('This device is managed by your parent.', style: GoogleFonts.outfit(fontSize: 5.5, color: const Color(0xFF374151)), textAlign: TextAlign.center),
        ]))),
      ])),
    );
  }

  Widget _desktopRestrictedPhoneMockup({required String headline, required List<String> tasks}) {
    return Container(
      width: 130, height: 250,
      decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF1E293B), width: 3.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))]),
      child: ClipRRect(borderRadius: BorderRadius.circular(17), child: Column(children: [
        Container(height: 12, color: const Color(0xFF1E293B), child: Center(child: Container(width: 34, height: 5, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(3))))),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Column(children: [
          const Icon(Icons.warning_amber_rounded, size: 28, color: Colors.white),
          const SizedBox(height: 4),
          Text(headline, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Container(width: double.infinity, padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('YOUR TASKS', style: GoogleFonts.outfit(fontSize: 6.5, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 3),
              ...tasks.take(2).map((t) => Text(t, style: GoogleFonts.outfit(fontSize: 6, color: Colors.white70), overflow: TextOverflow.ellipsis)),
            ])),
          const SizedBox(height: 8),
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 5), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Text('GOT IT', style: GoogleFonts.outfit(fontSize: 7, fontWeight: FontWeight.w900, color: const Color(0xFFEF4444)), textAlign: TextAlign.center)),
        ]))),
      ])),
    );
  }

  void _desktopShowLockPreview(Color textColor) {
    final tasks = _taskListCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final heading = _lockHeadlineCtrl.text.isEmpty ? 'LOCKED' : _lockHeadlineCtrl.text;
    final title = _taskTitleCtrl.text.isEmpty ? 'Parent Tasks' : _taskTitleCtrl.text;
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 340, padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: widget.isDark ? const Color(0xFF0F1A35) : Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.5))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Lock Screen Preview', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
          const SizedBox(height: 20),
          Container(
            width: 220, height: 400,
            decoration: BoxDecoration(color: const Color(0xFFFBBF24), borderRadius: BorderRadius.circular(32), border: Border.all(color: const Color(0xFF1E293B), width: 4.5)),
            child: ClipRRect(borderRadius: BorderRadius.circular(28), child: Column(children: [
              Container(height: 18, color: const Color(0xFF1E293B), child: Center(child: Container(width: 44, height: 7, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(3.5))))),
              Expanded(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1E293B), width: 2.5)), child: const Icon(Icons.add, color: Color(0xFF1E293B), size: 22)),
                const SizedBox(height: 10),
                Text(heading, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B), letterSpacing: 2)),
                const SizedBox(height: 14),
                Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('YOUR TASKS', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B))),
                    Text(title, style: GoogleFonts.outfit(fontSize: 9, color: const Color(0xFF374151))),
                    const SizedBox(height: 6),
                    ...tasks.take(4).map((t) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• $t', style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF374151))))),
                  ])),
                const SizedBox(height: 12),
                Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.send_rounded, color: Colors.white, size: 14), const SizedBox(width: 6), Text('SEND MESSAGE HERE', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))])),
                const SizedBox(height: 10),
                Text('This device is managed by your parent.\nComplete tasks to unlock.', style: GoogleFonts.outfit(fontSize: 9, color: const Color(0xFF374151)), textAlign: TextAlign.center),
              ]))),
            ])),
          ),
          const SizedBox(height: 20),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: GoogleFonts.outfit(color: const Color(0xFF22C55E), fontWeight: FontWeight.w700))),
        ]),
      ),
    ));
  }

  void _desktopShowRestrictedPreview(Color textColor) {
    final tasks = _warningListCtrl.text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    final headline = _restHeadlineCtrl.text.isEmpty ? 'APP RESTRICTED' : _restHeadlineCtrl.text;
    final msg = _restMsgCtrl.text.isEmpty ? 'Access to this application is restricted by parent settings.' : _restMsgCtrl.text;
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 340, padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: widget.isDark ? const Color(0xFF0F1A35) : Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('App Restricted Preview', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
          const SizedBox(height: 20),
          Container(
            width: 220, height: 400,
            decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(32), border: Border.all(color: const Color(0xFF1E293B), width: 4.5)),
            child: ClipRRect(borderRadius: BorderRadius.circular(28), child: Column(children: [
              Container(height: 18, color: const Color(0xFF1E293B), child: Center(child: Container(width: 44, height: 7, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(3.5))))),
              Expanded(child: Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.white)),
                const SizedBox(height: 14),
                Text(headline, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(msg, style: GoogleFonts.outfit(fontSize: 10, color: Colors.white70), textAlign: TextAlign.center),
                const SizedBox(height: 14),
                if (tasks.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('YOUR TASKS', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 5),
                    ...tasks.take(4).map((t) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• $t', style: GoogleFonts.outfit(fontSize: 10, color: Colors.white70)))),
                  ])),
                const SizedBox(height: 14),
                Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Text('GOT IT', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w900, color: const Color(0xFFEF4444)), textAlign: TextAlign.center)),
              ]))),
            ])),
          ),
          const SizedBox(height: 20),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontWeight: FontWeight.w700))),
        ]),
      ),
    ));
  }

  Widget _buildInputField(String label, String hint, TextEditingController controller, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.outfit(color: widget.textColor, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8).withOpacity(0.5), fontSize: 14),
            filled: true,
            fillColor: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 12), child: Text(title, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 2))),
        Container(
          decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF64748B), width: 0.5)),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingTile(String title, String subtitle, IconData icon, {String? trailing, bool hasSwitch = false, bool switchValue = false, bool isSuccess = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: const Color(0xFF64748B).withOpacity(0.1), width: 0.5))),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: (isSuccess ? const Color(0xFF10B981) : const Color(0xFF6366F1)).withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: isSuccess ? const Color(0xFF10B981) : const Color(0xFF6366F1), size: 20)),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: widget.textColor)), Text(subtitle, style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8)))])),
          if (trailing != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(trailing, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF6366F1)))),
          if (hasSwitch) Switch(value: switchValue, onChanged: (v) {}, activeColor: const Color(0xFF6366F1)),
          if (trailing == null && !hasSwitch) const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }
}

class _SuperAdminStatsCard extends StatelessWidget {
  final bool isDark; final bool isMobile;
  const _SuperAdminStatsCard({required this.isDark, required this.isMobile});
  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF18181B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final borderColor = const Color(0xFF64748B);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF6366F1)),
          const SizedBox(width: 8),
          Text('Global System Statistics', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
        ]),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('Permission Denied.', style: TextStyle(color: Colors.red)));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            int totalUsers = snapshot.data!.docs.length;
            int superAdmins = snapshot.data!.docs.where((d) => (d.data() as Map)['role'] == 'super_admin').length;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCompactStat('Total Tenants', totalUsers.toString(), const Color(0xFF10B981)),
                _buildCompactStat('Admin Roles', superAdmins.toString(), const Color(0xFFA855F7)),
                _buildCompactStat('Status', 'Healthy', const Color(0xFF3B82F6)),
              ],
            );
          }
        )
      ]),
    );
  }
  
  Widget _buildCompactStat(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
      Text(label, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8))),
    ]);
  }
}

// ─── Payment Methods (super_admin) ────────────────────────────────────────────
class _PaymentMethodsView extends StatefulWidget {
  final bool isDark;
  final Color cardColor, textColor, borderColor;
  const _PaymentMethodsView({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor});
  @override State<_PaymentMethodsView> createState() => _PaymentMethodsViewState();
}
class _PaymentMethodsViewState extends State<_PaymentMethodsView> {
  final _nameCtrl = TextEditingController();
  final _iconCtrl = TextEditingController();
  final _acctNameCtrl = TextEditingController();
  final _acctNumCtrl = TextEditingController();
  final _qrCtrl = TextEditingController();

  @override void dispose() { _nameCtrl.dispose(); _iconCtrl.dispose(); _acctNameCtrl.dispose(); _acctNumCtrl.dispose(); _qrCtrl.dispose(); super.dispose(); }

  void _clearCtrl() { _nameCtrl.clear(); _iconCtrl.clear(); _acctNameCtrl.clear(); _acctNumCtrl.clear(); _qrCtrl.clear(); }

  void _showAddEdit(BuildContext context, {Map<String, dynamic>? existing, String? docId}) {
    if (existing != null) {
      _nameCtrl.text = existing['name'] ?? '';
      _iconCtrl.text = existing['icon'] ?? '';
      _acctNameCtrl.text = existing['accountName'] ?? '';
      _acctNumCtrl.text = existing['accountNumber'] ?? '';
      _qrCtrl.text = existing['qrUrl'] ?? '';
    } else {
      _clearCtrl();
    }
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: widget.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(existing == null ? 'Add Payment Method' : 'Edit Payment Method', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: widget.textColor)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field('Name (e.g. GCash)', _nameCtrl),
              _field('Icon (emoji, e.g. 📱)', _iconCtrl),
              _field('Account Name', _acctNameCtrl),
              _field('Account Number', _acctNumCtrl),
              _field('QR Code Image URL (optional)', _qrCtrl),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              if (_nameCtrl.text.trim().isEmpty) return;
              final data = {
                'name': _nameCtrl.text.trim(),
                'icon': _iconCtrl.text.trim().isEmpty ? '💰' : _iconCtrl.text.trim(),
                'accountName': _acctNameCtrl.text.trim(),
                'accountNumber': _acctNumCtrl.text.trim(),
                'qrUrl': _qrCtrl.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              };
              if (docId != null) {
                await FirebaseFirestore.instance.collection('payment_methods').doc(docId).update(data);
              } else {
                await FirebaseFirestore.instance.collection('payment_methods').add(data);
              }
              if (dlgCtx.mounted) Navigator.pop(dlgCtx);
            },
            child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: ctrl,
      style: GoogleFonts.outfit(color: widget.textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: widget.borderColor.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1))),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Payment Methods', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: widget.textColor)),
            Text('Manage payment options shown to users during subscription upgrade', style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8))),
          ])),
          ElevatedButton.icon(
            onPressed: () => _showAddEdit(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Add Method', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          ),
        ]),
        const SizedBox(height: 20),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('payment_methods').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if (docs.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(48), child: Text('No payment methods yet. Add one above.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))));
            return Column(children: docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: widget.borderColor.withOpacity(0.3))),
                child: Row(children: [
                  Text(d['icon'] as String? ?? '💰', style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['name'] as String? ?? '', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15, color: widget.textColor)),
                    if ((d['accountName'] as String? ?? '').isNotEmpty)
                      Text('${d['accountName']} · ${d['accountNumber']}', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8))),
                    if ((d['qrUrl'] as String? ?? '').isNotEmpty)
                      Text('QR: ${d['qrUrl']}', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF6366F1)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  IconButton(icon: const Icon(Icons.edit_rounded, color: Color(0xFF6366F1), size: 20), onPressed: () => _showAddEdit(context, existing: d, docId: doc.id)),
                  IconButton(icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20), onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                      backgroundColor: widget.cardColor,
                      title: Text('Delete ${d['name']}?', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: widget.textColor)),
                      content: Text('This will remove this payment method for all users.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
                        ElevatedButton(onPressed: () => Navigator.pop(_, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white))),
                      ],
                    ));
                    if (ok == true) await FirebaseFirestore.instance.collection('payment_methods').doc(doc.id).delete();
                  }),
                ]),
              );
            }).toList());
          },
        ),
      ]),
    );
  }
}

// ─── Pending Transactions (super_admin) ───────────────────────────────────────
class _PendingTransactionsView extends StatelessWidget {
  final bool isDark;
  final Color cardColor, textColor, borderColor;
  const _PendingTransactionsView({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor});

  Future<void> _approve(BuildContext context, String txId, String uid, String planId, Color cardColor, Color textColor) async {
    // Auto-load duration from the plan definition
    String durationUnit = 'months';
    int durationValue = 1;
    bool autoFilled = false;
    try {
      final planDoc = await FirebaseFirestore.instance.collection('plans').doc(planId).get();
      if (planDoc.exists) {
        final pd = planDoc.data() as Map<String, dynamic>;
        if (pd['durationUnit'] != null) {
          durationUnit = pd['durationUnit'] as String;
          durationValue = (pd['durationValue'] as num?)?.toInt() ?? 1;
          autoFilled = true;
        }
      }
    } catch (_) {}
    final valueCtrl = TextEditingController(text: durationValue.toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Approve Payment', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (autoFilled)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4))),
                child: Row(children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFF22C55E), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Duration auto-filled from plan: $durationValue ${durationUnit == 'lifetime' ? 'lifetime' : durationUnit}', style: GoogleFonts.outfit(color: const Color(0xFF22C55E), fontSize: 12, fontWeight: FontWeight.w600))),
                ]),
              ),
            Text('This will activate the plan for this user.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
            const SizedBox(height: 16),
            Text('DURATION TYPE', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.4)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFF64748B).withOpacity(0.4)), borderRadius: BorderRadius.circular(12), color: cardColor),
              child: DropdownButton<String>(
                value: durationUnit,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: cardColor,
                style: GoogleFonts.outfit(color: textColor, fontSize: 14),
                items: const [
                  DropdownMenuItem(value: 'days',     child: Text('Days (1–30)')),
                  DropdownMenuItem(value: 'months',   child: Text('Months')),
                  DropdownMenuItem(value: 'years',    child: Text('Years')),
                  DropdownMenuItem(value: 'lifetime', child: Text('Lifetime')),
                ],
                onChanged: (v) { if (v != null) setS(() { durationUnit = v; valueCtrl.text = '1'; durationValue = 1; }); },
              ),
            ),
            if (durationUnit != 'lifetime') ...[
              const SizedBox(height: 14),
              Text(
                durationUnit == 'days' ? 'DAYS (1–30)' : durationUnit == 'months' ? 'MONTHS' : 'YEARS',
                style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.4),
              ),
              const SizedBox(height: 8),
              durationUnit == 'days'
                ? Wrap(spacing: 8, runSpacing: 8, children: List.generate(30, (i) {
                    final v = i + 1;
                    final sel = durationValue == v;
                    return GestureDetector(
                      onTap: () => setS(() { durationValue = v; valueCtrl.text = v.toString(); }),
                      child: Container(
                        width: 40, height: 36,
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF22C55E) : const Color(0xFF22C55E).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF22C55E).withOpacity(sel ? 1 : 0.3)),
                        ),
                        child: Center(child: Text('$v', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : const Color(0xFF22C55E)))),
                      ),
                    );
                  }))
                : TextField(
                    controller: valueCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.outfit(color: textColor),
                    onChanged: (v) => durationValue = int.tryParse(v) ?? 1,
                    decoration: InputDecoration(
                      hintText: durationUnit == 'months' ? 'e.g. 3' : 'e.g. 1',
                      hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixText: durationUnit,
                      suffixStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFBBF24).withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.4))),
                  child: Row(children: [
                    const Icon(Icons.all_inclusive_rounded, color: Color(0xFFFBBF24), size: 20),
                    const SizedBox(width: 8),
                    Text('Lifetime access — never expires', style: GoogleFonts.outfit(color: const Color(0xFFFBBF24), fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                ),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(_, true),
              child: Text('Approve & Activate', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    DateTime expiry;
    if (durationUnit == 'lifetime') {
      expiry = DateTime(2099, 12, 31);
    } else if (durationUnit == 'days') {
      final days = durationValue.clamp(1, 30);
      expiry = DateTime.now().add(Duration(days: days));
    } else if (durationUnit == 'months') {
      final months = durationValue < 1 ? 1 : durationValue;
      final now = DateTime.now();
      expiry = DateTime(now.year, now.month + months, now.day);
    } else {
      final years = durationValue < 1 ? 1 : durationValue;
      final now = DateTime.now();
      expiry = DateTime(now.year + years, now.month, now.day);
    }
    final batch = FirebaseFirestore.instance.batch();
    batch.update(FirebaseFirestore.instance.collection('transactions').doc(txId), {
      'status': 'approved', 'approvedAt': FieldValue.serverTimestamp(), 'approvedBy': FirebaseAuth.instance.currentUser?.uid,
    });
    batch.update(FirebaseFirestore.instance.collection('users').doc(uid), {
      'plan': planId, 'expiryDate': Timestamp.fromDate(expiry), 'planActivatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan activated successfully!'), backgroundColor: Color(0xFF22C55E)));
    }
  }

  Future<void> _reject(BuildContext context, String txId, Color cardColor, Color textColor) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reject Payment', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Optionally provide a reason for rejection:', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
          const SizedBox(height: 10),
          TextField(
            controller: reasonCtrl,
            style: GoogleFonts.outfit(color: textColor),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Reason (optional)…',
              hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(_, true),
            child: Text('Reject', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseFirestore.instance.collection('transactions').doc(txId).update({
      'status': 'rejected', 'rejectedAt': FieldValue.serverTimestamp(), 'rejectionReason': reasonCtrl.text.trim(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction rejected.'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Pending Payments', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: textColor)),
        Text('Review and approve subscription payment submissions from users', style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8))),
        const SizedBox(height: 20),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('transactions').orderBy('submittedAt', descending: true).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if (docs.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(48), child: Text('No transactions yet.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))));

            final pending = docs.where((d) => (d.data() as Map)['status'] == 'pending').toList();
            final others = docs.where((d) => (d.data() as Map)['status'] != 'pending').toList();

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (pending.isNotEmpty) ...[
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFFBBF24).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: Text('PENDING  ${pending.length}', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFFFBBF24)))),
                ]),
                const SizedBox(height: 10),
                ...pending.map((doc) => _buildCard(context, doc, isPending: true)),
                const SizedBox(height: 20),
              ],
              if (others.isNotEmpty) ...[
                Text('HISTORY', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 1.2)),
                const SizedBox(height: 10),
                ...others.map((doc) => _buildCard(context, doc, isPending: false)),
              ],
            ]);
          },
        ),
      ]),
    );
  }

  Widget _buildCard(BuildContext context, QueryDocumentSnapshot doc, {required bool isPending}) {
    final d = doc.data() as Map<String, dynamic>;
    final status = d['status'] as String? ?? 'pending';
    final statusColor = status == 'approved' ? const Color(0xFF22C55E) : status == 'rejected' ? Colors.redAccent : const Color(0xFFFBBF24);
    final submittedAt = (d['submittedAt'] as Timestamp?)?.toDate();
    final dateStr = submittedAt != null ? '${submittedAt.day}/${submittedAt.month}/${submittedAt.year}' : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: isPending ? const Color(0xFFFBBF24).withOpacity(0.4) : borderColor.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['userEmail'] as String? ?? 'Unknown', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14, color: textColor)),
            Text('Plan: ${(d['planName'] ?? d['planId'] ?? '').toString()}  ·  Via: ${d['paymentMethod'] ?? '—'}  ·  $dateStr', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(status.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor)),
          ),
        ]),
        if ((d['proofUrl'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {}, 
            child: Text('Proof: ${d['proofUrl']}', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF6366F1), decoration: TextDecoration.underline), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
        if (isPending) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _reject(context, doc.id, cardColor, textColor),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text('Reject', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _approve(context, doc.id, d['uid'] as String? ?? '', d['planId'] as String? ?? '', cardColor, textColor),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: Text('Approve', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )),
          ]),
        ],
      ]),
    );
  }
}

class _UsersList extends StatelessWidget {
  final bool isDark; final Color cardColor; final Color textColor; final Color borderColor; final bool isMobile;
  const _UsersList({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Users Admin', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _showAddTenantDialog(context), icon: const Icon(Icons.person_add_rounded), label: const Text('Add Tenant'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12))),
      ]),
      const SizedBox(height: 24),
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Firestore Permission Denied.\nPlease update your Firebase Security Rules.', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: Colors.red, fontSize: 16))));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final users = snapshot.data!.docs;
          return Container(
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor, width: 0.5)),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: users.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: borderColor.withOpacity(0.3)),
              itemBuilder: (context, index) {
                final u = users[index].data() as Map<String, dynamic>;
                return ListTile(
                  leading: CircleAvatar(backgroundColor: const Color(0xFF6366F1).withOpacity(0.2), child: const Icon(Icons.person, color: Color(0xFF6366F1))),
                  title: Text(u['email'] ?? u['role'] ?? 'Unknown User', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textColor)),
                  subtitle: Text('Role: ${u['role'] ?? 'parent'}', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12)),
                  trailing: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: textColor.withOpacity(0.5)),
                    onSelected: (val) {
                      if (val == 'delete') {
                         FirebaseFirestore.instance.collection('users').doc(users[index].id).delete();
                      } else {
                         FirebaseFirestore.instance.collection('users').doc(users[index].id).update({'role': val});
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'super_admin', child: Text('Make Super Admin', style: GoogleFonts.outfit())),
                      PopupMenuItem(value: 'admin', child: Text('Make Admin (Tenant)', style: GoogleFonts.outfit())),
                      PopupMenuItem(value: 'parent', child: Text('Make Parent', style: GoogleFonts.outfit())),
                      PopupMenuItem(value: 'delete', child: Text('Delete User', style: GoogleFonts.outfit(color: Colors.red))),
                    ]
                  ),
                );
              },
            ),
          );
        }
      )
    ]);
  }

  void _showAddTenantDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: borderColor, width: 0.5)),
        title: Text('Add New Tenant', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor)),
        content: Text(
          'To add a new tenant, instruct the user to sign up through the login page using their own credentials.\n\nOnce they create an account, their email will appear in this list and you can adjust their role to "Admin (Tenant)" here.',
          style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Got It', style: GoogleFonts.outfit(color: const Color(0xFF6366F1), fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}

class _SubscriptionView extends StatelessWidget {
  final bool isDark; final Color cardColor; final Color textColor; final Color borderColor; final String userRole;
  const _SubscriptionView({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
        final currentPlan = (userData['plan'] ?? 'free').toString().toLowerCase();
        final expiryDate = (userData['expiryDate'] as Timestamp?)?.toDate();
        final bool isExpired = expiryDate != null && expiryDate.isBefore(DateTime.now());

        _syncSubscriptionToDevices(currentPlan, isExpired);

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('plans').orderBy('deviceLimit').snapshots(),
          builder: (context, planSnapshot) {
            if (!planSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            final plans = planSnapshot.data!.docs;

            // If no plans exist, provide a button to initialize default plans (Super Admin only)
            if (plans.isEmpty && userRole == 'super_admin') {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('No subscription plans found.', style: GoogleFonts.outfit(color: textColor)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: () => _initializeDefaultPlans(), child: const Text('Initialize Default Plans')),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Subscription Plans', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
                        const SizedBox(height: 8),
                        Text(userRole == 'super_admin' ? 'Manage global subscription tiers.' : 'Manage your account limits and features.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
                      ],
                    ),
                    const Spacer(),
                    if (userRole == 'super_admin') 
                      ElevatedButton.icon(
                        onPressed: () => _showPlanDialog(context), 
                        icon: const Icon(Icons.add_rounded), 
                        label: const Text('Create Plan'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                  ],
                ),
                const SizedBox(height: 32),

                if (userRole != 'super_admin') ...[
                  if (isExpired && currentPlan != 'free')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.redAccent)),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Your subscription has expired! All blocking features and settings are currently paused.', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    )
                  else if (currentPlan == 'free')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF6366F1))),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFF6366F1)),
                          const SizedBox(width: 12),
                          Expanded(child: Text('You are on the Free Plan. Limited to 1 device.', style: GoogleFonts.outfit(color: const Color(0xFF6366F1), fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                ],

                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: plans.map((doc) {
                    final p = doc.data() as Map<String, dynamic>;
                    final name = p['name'] ?? 'Plan';
                    final price = (p['price'] ?? '0').toString();
                    final limit = (p['deviceLimit'] ?? 1).toString();
                    final blockedLimit = (p['blockedAppsLimit'] ?? 0).toString();
                    final hiddenLimit = (p['hiddenAppsLimit'] ?? 0).toString();
                    final features = (p['features'] as List? ?? []).map((e) => e.toString()).toList();
                    final colorHex = p['color'] ?? '0xFF64748B';
                    final Color planColor = Color(int.parse(colorHex));
                    final planDurationUnit  = (p['durationUnit']  ?? 'months').toString();
                    final planDurationValue = (p['durationValue'] as num?)?.toInt() ?? 1;

                    final currentDoc = plans.firstWhere((element) => element.id == currentPlan, orElse: () => plans.first);
                    final currentPrice = double.tryParse((currentDoc.data() as Map)['price'].toString()) ?? 0.0;
                    final thisPrice = double.tryParse(price) ?? 0.0;

                    return SizedBox(
                       width: 350,
                       child: _buildPlanCard(
                         context, 
                         doc.id,
                         name, 
                         price, 
                         '$limit Device${limit == "1" ? "" : "s"}', 
                         features, 
                         currentPlan == doc.id.toLowerCase() && !isExpired, 
                         currentPlan == doc.id.toLowerCase(), 
                         planColor,
                         blockedLimit: blockedLimit,
                         hiddenLimit: hiddenLimit,
                         thisPrice: thisPrice,
                         currentPrice: currentPrice,
                         durationUnit: planDurationUnit,
                         durationValue: planDurationValue,
                       ),
                    );
                  }).toList(),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _syncSubscriptionToDevices(String plan, bool isExpired) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    bool isActive = !(isExpired && plan != 'free');

    final devices = await FirebaseFirestore.instance.collection('devices').where('parentUid', isEqualTo: uid).get();
    for (var doc in devices.docs) {
      final data = doc.data();
      final Map<String, dynamic> updates = {};
      if (data['subscriptionActive'] != isActive) updates['subscriptionActive'] = isActive;
      if (!isActive) {
        final hasSchedules = (data['lockSchedules'] as List?)?.isNotEmpty == true;
        final hasAppSchedules = (data['appSchedules'] as Map?)?.isNotEmpty == true;
        final isLocked = data['locked'] == true;
        if (hasSchedules) updates['lockSchedules'] = [];
        if (hasAppSchedules) updates['appSchedules'] = {};
        if (isLocked) updates['locked'] = false;
      }
      if (updates.isNotEmpty) doc.reference.update(updates);
    }
  }

  void _initializeDefaultPlans() async {
    final batch = FirebaseFirestore.instance.batch();
    final col = FirebaseFirestore.instance.collection('plans');

    Map<String, dynamic> feats({bool restrictions = true, bool schedule = true, bool filter = true,
      bool monitoring = true, bool location = true, bool chat = true, bool pin = true}) => {
      'appRestrictions': restrictions, 'scheduleLock': schedule, 'appFilter': filter,
      'childMonitoring': monitoring, 'liveLocation': location, 'chat': chat, 'masterPin': pin,
    };

    batch.set(col.doc('trial'), {
      'name': 'Trial', 'price': 0, 'deviceLimit': 1, 'blockedAppsLimit': 1, 'hiddenAppsLimit': 0,
      'featuresMap': feats(restrictions: true, schedule: false, filter: false, monitoring: false, location: true, chat: true, pin: false),
      'features': ['1 App Restriction', '3-Day Free Trial', 'Live Location'],
      'color': '0xFFFBBF24', 'durationUnit': 'days', 'durationValue': 3,
    });
    batch.set(col.doc('free'), {
      'name': 'Free', 'price': 0, 'deviceLimit': 1, 'blockedAppsLimit': 5, 'hiddenAppsLimit': 0,
      'featuresMap': feats(restrictions: true, schedule: false, filter: false, monitoring: false, location: false, chat: true, pin: false),
      'features': ['5 App Restrictions', 'Manual Lock'],
      'color': '0xFF94A3B8', 'durationUnit': 'lifetime', 'durationValue': 0,
    });
    batch.set(col.doc('starter'), {
      'name': 'Starter', 'price': 10, 'deviceLimit': 3, 'blockedAppsLimit': 20, 'hiddenAppsLimit': 10,
      'featuresMap': feats(restrictions: true, schedule: true, filter: true, monitoring: true, location: true, chat: true, pin: true),
      'features': ['Real-time Tracking', 'App Blocking', 'Geofencing'],
      'color': '0xFF10B981', 'durationUnit': 'months', 'durationValue': 1,
    });
    batch.set(col.doc('pro'), {
      'name': 'Pro', 'price': 25, 'deviceLimit': 10, 'blockedAppsLimit': 999, 'hiddenAppsLimit': 999,
      'featuresMap': feats(),
      'features': ['Priority Support', 'Usage Timeline', 'Unlimited History'],
      'color': '0xFF6366F1', 'durationUnit': 'months', 'durationValue': 1,
    });

    await batch.commit();
  }

  Widget _buildPlanCard(BuildContext context, String id, String name, String price, String limit, List<String> features, bool isActive, bool isCurrent, Color color, {String blockedLimit = "0", String hiddenLimit = "0", double thisPrice = 0, double currentPrice = 0, String durationUnit = 'months', int durationValue = 1}) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor, 
        borderRadius: BorderRadius.circular(32), 
        border: Border.all(color: isCurrent ? color : borderColor, width: isCurrent ? 2 : 0.5),
        boxShadow: isCurrent ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isCurrent) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)), child: Text('CURRENT PLAN', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white))),
              if (userRole == 'super_admin') 
                Row(
                  children: [
                    IconButton(onPressed: () => _showPlanDialog(context, id: id, existing: {
                       'name': name, 'price': price, 'deviceLimit': limit.split(' ')[0], 'features': features, 'color': '0x${color.value.toRadixString(16).toUpperCase()}',
                       'blockedAppsLimit': blockedLimit, 'hiddenAppsLimit': hiddenLimit,
                       'durationUnit': durationUnit, 'durationValue': durationValue,
                    }), icon: const Icon(Icons.edit_rounded, size: 18), color: const Color(0xFF94A3B8)),
                    IconButton(onPressed: () => FirebaseFirestore.instance.collection('plans').doc(id).delete(), icon: const Icon(Icons.delete_outline_rounded, size: 18), color: Colors.redAccent),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(name, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 8),
          Row(children: [
            Text('\$', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            Text(price, style: GoogleFonts.outfit(fontSize: 36, fontWeight: FontWeight.w900, color: textColor)),
            Text(_durationSuffix(durationUnit, durationValue), style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF94A3B8))),
          ]),
          const SizedBox(height: 16),
          Text(limit, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text('$blockedLimit Restricted Apps allowed', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: color.withOpacity(0.8))),
          Text('$hiddenLimit Filtered Apps allowed', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: color.withOpacity(0.8))),
          const SizedBox(height: 24),
          ...features.map((f) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Icon(Icons.check_circle_rounded, size: 16, color: color), const SizedBox(width: 10), Expanded(child: Text(f, style: GoogleFonts.outfit(fontSize: 13, color: textColor)))]))).toList(),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isCurrent && isActive ? null : () => _upgradePlan(context, id.toLowerCase(), name),
              style: ElevatedButton.styleFrom(
                backgroundColor: color, 
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                disabledBackgroundColor: color.withOpacity(0.1),
              ),
              child: Text(
                isCurrent && isActive ? 'CURRENT PLAN' : 
                (isCurrent ? 'RENEW' : (thisPrice > currentPrice ? 'UPGRADE' : 'DOWNGRADE')), 
                style: GoogleFonts.outfit(fontWeight: FontWeight.w900, letterSpacing: 1)
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlanDialog(BuildContext context, {String? id, Map<String, dynamic>? existing}) {
    final nameCtrl    = TextEditingController(text: existing?['name']);
    final priceCtrl   = TextEditingController(text: (existing?['price'] ?? '').toString());
    final limitCtrl   = TextEditingController(text: (existing?['deviceLimit'] ?? '').toString());
    final blockedCtrl = TextEditingController(text: (existing?['blockedAppsLimit'] ?? '5').toString());
    final hiddenCtrl  = TextEditingController(text: (existing?['hiddenAppsLimit'] ?? '2').toString());
    final colorCtrl   = TextEditingController(text: existing?['color'] ?? '0xFF6366F1');
    final List<TextEditingController> featureCtrls = (existing?['features'] as List? ?? [''])
        .map((f) => TextEditingController(text: f.toString())).toList();

    // Feature toggles (Map<String,bool>) — replaces the legacy free-text feature list
    final Map<String, dynamic> existingFeats = (existing?['featuresMap'] is Map)
        ? Map<String, dynamic>.from(existing!['featuresMap'] as Map)
        : <String, dynamic>{};
    final Map<String, bool> toggles = {
      'appRestrictions':  (existingFeats['appRestrictions']  as bool?) ?? true,
      'scheduleLock':     (existingFeats['scheduleLock']     as bool?) ?? true,
      'appFilter':        (existingFeats['appFilter']        as bool?) ?? true,
      'childMonitoring':  (existingFeats['childMonitoring']  as bool?) ?? true,
      'liveLocation':     (existingFeats['liveLocation']     as bool?) ?? true,
      'chat':             (existingFeats['chat']             as bool?) ?? true,
      'masterPin':        (existingFeats['masterPin']        as bool?) ?? true,
    };
    const Map<String, String> toggleLabels = {
      'appRestrictions':  'App Restrictions',
      'scheduleLock':     'Schedule Lock',
      'appFilter':        'App Filter',
      'childMonitoring':  'Child Activity Monitoring',
      'liveLocation':     'Live Location',
      'chat':             'Parent ↔ Child Chat',
      'masterPin':        'Master PIN',
    };

    String durationUnit = existing?['durationUnit'] ?? 'months';
    int durationValue   = existing?['durationValue'] ?? 1;
    final durValueCtrl  = TextEditingController(text: durationValue.toString());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(id == null ? 'Create New Plan' : 'Edit Plan', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildField('Plan Name', nameCtrl),
                _buildField(r'Price ($)', priceCtrl, isNum: true),
                _buildField('Max Devices', limitCtrl, isNum: true),
                _buildField('Max Restricted Apps', blockedCtrl, isNum: true),
                _buildField('Max Filtered Apps', hiddenCtrl, isNum: true),
                _buildField('Hex Color (e.g. 0xFF6366F1)', colorCtrl),

                Text('PLAN DURATION', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(border: Border.all(color: borderColor.withOpacity(0.3)), borderRadius: BorderRadius.circular(12), color: cardColor),
                  child: DropdownButton<String>(
                    value: durationUnit,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: cardColor,
                    style: GoogleFonts.outfit(color: textColor, fontSize: 14),
                    items: const [
                      DropdownMenuItem(value: 'days',     child: Text('Days (1–30)')),
                      DropdownMenuItem(value: 'months',   child: Text('Months')),
                      DropdownMenuItem(value: 'years',    child: Text('Years')),
                      DropdownMenuItem(value: 'lifetime', child: Text('Lifetime')),
                    ],
                    onChanged: (v) { if (v != null) setDialogState(() { durationUnit = v; durationValue = 1; durValueCtrl.text = '1'; }); },
                  ),
                ),
                const SizedBox(height: 12),
                if (durationUnit == 'days') ...[
                  Text('SELECT DAYS', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.4)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: List.generate(30, (i) {
                    final v = i + 1; final sel = durationValue == v;
                    return GestureDetector(
                      onTap: () => setDialogState(() { durationValue = v; durValueCtrl.text = v.toString(); }),
                      child: Container(
                        width: 40, height: 36,
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF6366F1) : const Color(0xFF6366F1).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF6366F1).withOpacity(sel ? 1 : 0.3)),
                        ),
                        child: Center(child: Text('$v', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : const Color(0xFF6366F1)))),
                      ),
                    );
                  })),
                ] else if (durationUnit == 'lifetime')
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFBBF24).withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.4))),
                    child: Row(children: [
                      const Icon(Icons.all_inclusive_rounded, color: Color(0xFFFBBF24), size: 20),
                      const SizedBox(width: 8),
                      Text('Access never expires', style: GoogleFonts.outfit(color: const Color(0xFFFBBF24), fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                  )
                else
                  _buildField(durationUnit == 'months' ? 'Number of Months' : 'Number of Years', durValueCtrl, isNum: true),

                const SizedBox(height: 12),
                Text('FEATURE ACCESS', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(border: Border.all(color: borderColor.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: toggles.keys.map((k) => SwitchListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(toggleLabels[k] ?? k, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                      value: toggles[k] ?? true,
                      activeColor: const Color(0xFF6366F1),
                      onChanged: (v) => setDialogState(() => toggles[k] = v),
                    )).toList(),
                  ),
                ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('MARKETING BULLETS', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => setDialogState(() => featureCtrls.add(TextEditingController())),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF6366F1)),
                    ),
                  ],
                ),
                ...featureCtrls.asMap().entries.map((entry) {
                  int idx = entry.key; var ctrl = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(child: _buildField('Feature ${idx + 1}', ctrl)),
                      IconButton(
                        onPressed: () => setDialogState(() => featureCtrls.removeAt(idx)),
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: Colors.redAccent),
                      ),
                    ]),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
            ElevatedButton(
              onPressed: () async {
                final parsedDurValue = durationUnit == 'lifetime' ? 0 : (int.tryParse(durValueCtrl.text) ?? durationValue).clamp(1, durationUnit == 'days' ? 30 : 999);
                final planData = {
                  'name': nameCtrl.text.trim(),
                  'price': double.tryParse(priceCtrl.text) ?? 0.0,
                  'deviceLimit': int.tryParse(limitCtrl.text) ?? 1,
                  'blockedAppsLimit': int.tryParse(blockedCtrl.text) ?? 0,
                  'hiddenAppsLimit': int.tryParse(hiddenCtrl.text) ?? 0,
                  'features': featureCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
                  'color': colorCtrl.text.trim(),
                  'durationUnit': durationUnit,
                  'durationValue': parsedDurValue,
                };
                if (id == null) {
                  await FirebaseFirestore.instance.collection('plans').doc(nameCtrl.text.trim().toLowerCase()).set(planData);
                } else {
                  await FirebaseFirestore.instance.collection('plans').doc(id).update(planData);
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text('Save Plan', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  String _durationSuffix(String unit, int value) {
    if (unit == 'lifetime') return ' one-time';
    if (unit == 'days')     return value == 1 ? '/day'  : '/$value days';
    if (unit == 'years')    return value == 1 ? '/yr'   : '/$value yrs';
    return value == 1 ? '/mo' : '/$value mo';
  }

  Widget _buildField(String label, TextEditingController ctrl, {bool isNum = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        style: GoogleFonts.outfit(color: textColor),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1))),
        ),
      ),
    );
  }

  void _upgradePlan(BuildContext context, String planId, String planName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Step 1: Show payment method selection
    String? selectedMethod;
    String? proofUrl;
    bool _submitting = false;

    // Fetch payment methods from Firestore
    final pmSnap = await FirebaseFirestore.instance.collection('payment_methods').get();
    final paymentMethods = pmSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    if (paymentMethods.isEmpty) {
      paymentMethods.addAll([
        {'id': 'gcash', 'name': 'GCash', 'icon': '📱', 'qrUrl': '', 'accountName': 'AppLocker PH', 'accountNumber': '09XX-XXX-XXXX'},
        {'id': 'maya', 'name': 'Maya', 'icon': '💳', 'qrUrl': '', 'accountName': 'AppLocker PH', 'accountNumber': '09XX-XXX-XXXX'},
        {'id': 'bank', 'name': 'Bank Transfer', 'icon': '🏦', 'qrUrl': '', 'accountName': 'AppLocker PH', 'accountNumber': '0000-0000-0000'},
      ]);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setS) => AlertDialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          title: Row(children: [
            const Icon(Icons.payment_rounded, color: Color(0xFF6366F1)),
            const SizedBox(width: 10),
            Expanded(child: Text('Upgrade to $planName', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor, fontSize: 18))),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SELECT PAYMENT METHOD', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  ...paymentMethods.map((pm) {
                    final isSelected = selectedMethod == pm['id'];
                    return GestureDetector(
                      onTap: () => setS(() => selectedMethod = pm['id'] as String),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF6366F1).withOpacity(0.1) : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey.withOpacity(0.05)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF64748B).withOpacity(0.4), width: isSelected ? 1.5 : 0.5),
                        ),
                        child: Row(children: [
                          Text(pm['icon'] as String? ?? '💰', style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(pm['name'] as String? ?? '', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: textColor)),
                            if ((pm['accountName'] as String? ?? '').isNotEmpty)
                              Text('${pm['accountName']} · ${pm['accountNumber']}', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8))),
                          ])),
                          if (isSelected) const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1), size: 20),
                        ]),
                      ),
                    );
                  }).toList(),
                  if (selectedMethod != null) ...[
                    const SizedBox(height: 16),
                    Divider(color: const Color(0xFF64748B).withOpacity(0.3)),
                    const SizedBox(height: 12),
                    // Show QR code if available
                    Builder(builder: (_) {
                      final pm = paymentMethods.firstWhere((p) => p['id'] == selectedMethod, orElse: () => {});
                      final qrUrl = pm['qrUrl'] as String? ?? '';
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (qrUrl.isNotEmpty) ...[
                          Text('SCAN QR CODE', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 1.2)),
                          const SizedBox(height: 8),
                          Center(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(qrUrl, height: 180, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
                          const SizedBox(height: 12),
                        ],
                        Text('PROOF OF PAYMENT', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text('After paying, paste your screenshot URL or reference number below.', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8))),
                        const SizedBox(height: 8),
                        TextField(
                          onChanged: (v) => setS(() => proofUrl = v.trim()),
                          style: GoogleFonts.outfit(fontSize: 12, color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Reference # or image URL of receipt…',
                            hintStyle: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.receipt_long_rounded, color: Color(0xFF6366F1), size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            filled: true, fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.4))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.25))),
                          ),
                        ),
                      ]);
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
            ElevatedButton(
              onPressed: (selectedMethod == null || _submitting) ? null : () => Navigator.pop(dlgCtx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _submitting 
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Submit for Approval', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedMethod == null) return;

    // Save transaction to Firestore
    try {
      await FirebaseFirestore.instance.collection('transactions').add({
        'uid': uid,
        'planId': planId,
        'planName': planName,
        'paymentMethod': selectedMethod,
        'proofUrl': proofUrl ?? '',
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'userEmail': FirebaseAuth.instance.currentUser?.email ?? '',
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Payment submitted! Awaiting admin approval for $planName plan.'),
          backgroundColor: const Color(0xFF6366F1),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
    // NOTE: Actual plan activation happens when super_admin approves the transaction
  }

}

// ─── Locked overlay shown for plans without childMonitoring access ───────────
class _MonitoringLockedView extends StatelessWidget {
  final Color textColor;
  final bool expired;
  const _MonitoringLockedView({required this.textColor, this.expired = false});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)]),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.4)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)]), shape: BoxShape.circle),
            child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 18),
          Text(expired ? 'Subscription Expired' : 'Premium Feature',
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 10),
          Text(
            expired
                ? 'Your subscription has expired. Renew to continue tracking your child\'s activity.'
                : 'Upgrade your account to view child activity logs, app usage, and reports.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: () {
              html.window.localStorage['applocker_dashboard_menu'] = 'subscriptions';
              html.window.location.reload();
            },
            label: Text('Upgrade Now', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24), foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Helper: format duration milliseconds to human-readable ───────────────────
String _formatDuration(int ms) {
  if (ms <= 0) return '0s';
  final totalSecs = (ms / 1000).round();
  final mins = totalSecs ~/ 60;
  final secs = totalSecs % 60;
  if (mins == 0) return '${secs}s';
  if (secs == 0) return '${mins}m';
  return '${mins}m ${secs}s';
}


class _MonitoringView extends StatefulWidget {
  final bool isDark; final Color cardColor; final Color textColor; final Color borderColor; final bool isMobile;
  const _MonitoringView({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor, required this.isMobile});

  @override
  State<_MonitoringView> createState() => _MonitoringViewState();
}

class _MonitoringViewState extends State<_MonitoringView> with SingleTickerProviderStateMixin {
  String? _selectedDeviceId;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _clearHistory(BuildContext context, String collectionType) async {
    if (_selectedDeviceId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear History?', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: widget.textColor)),
        content: Text('This will permanently delete all $collectionType history for this device.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Clear All', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true || _selectedDeviceId == null) return;

    String typeFilter;
    if (collectionType == 'app usage') typeFilter = 'app_usage';
    else if (collectionType == 'web activity') typeFilter = 'url';
    else if (collectionType == 'social') typeFilter = 'message';  // social messages use 'message' type
    else typeFilter = 'telephony'; // custom case for both sms/call

    final batch = FirebaseFirestore.instance.batch();
    final baseQuery = FirebaseFirestore.instance
        .collection('devices')
        .doc(_selectedDeviceId)
        .collection('activity');

    final List<QueryDocumentSnapshot> allDocs = [];

    if (typeFilter == 'telephony') {
      // Clear both call and sms logs
      final callDocs = await baseQuery.where('type', isEqualTo: 'call').get();
      final smsDocs  = await baseQuery.where('type', isEqualTo: 'sms').get();
      allDocs.addAll(callDocs.docs);
      allDocs.addAll(smsDocs.docs);
    } else if (typeFilter == 'message') {
      // Social messages: clear both 'message' type AND any 'sms' type flagged as social
      final msgDocs = await baseQuery.where('type', isEqualTo: 'message').get();
      allDocs.addAll(msgDocs.docs);
    } else {
      final d = await baseQuery.where('type', isEqualTo: typeFilter).get();
      allDocs.addAll(d.docs);
    }

    for (final doc in allDocs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$collectionType history cleared.'), backgroundColor: const Color(0xFF10B981)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({String planId, bool expired})>(
      future: () async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return (planId: 'free', expired: false);
        return PlanGate.currentPlan(uid);
      }(),
      builder: (context, curSnap) {
        if (curSnap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final cur = curSnap.data ?? (planId: 'free', expired: false);
        return FutureBuilder<PlanFeatures>(
          future: PlanGate.load(cur.planId),
          builder: (context, planSnap) {
            if (planSnap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final feat = planSnap.data ?? const PlanFeatures();
            if (cur.expired || !feat.childMonitoring) {
              return _MonitoringLockedView(textColor: widget.textColor, expired: cur.expired);
            }
            return _buildMonitoringContent(context);
          },
        );
      },
    );
  }

  Widget _buildMonitoringContent(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final devices = snapshot.data!.docs;
        if (devices.isEmpty) return const Center(child: Text('No devices paired yet.'));

        if (_selectedDeviceId == null) _selectedDeviceId = devices.first.id;

        // Ensure selected device exists after device list changes
        final validId = devices.any((d) => d.id == _selectedDeviceId)
            ? _selectedDeviceId!
            : devices.first.id;
        if (validId != _selectedDeviceId) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedDeviceId = validId);
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Activity Overview', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: widget.textColor)),
                    const SizedBox(height: 4),
                    Text('Review app usage, web history, and message activity.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  width: 250,
                  decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: widget.borderColor.withOpacity(0.5))),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: validId,
                      dropdownColor: widget.cardColor,
                      isExpanded: true,
                      onChanged: (val) => setState(() => _selectedDeviceId = val),
                      items: devices.map((d) => DropdownMenuItem(value: d.id, child: Text(d.id, style: GoogleFonts.outfit(color: widget.textColor, fontWeight: FontWeight.w600)))).toList(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            // Tabs + Clear Button row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: widget.borderColor.withOpacity(0.1))),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: const Color(0xFF6366F1),
                      labelColor: const Color(0xFF6366F1),
                      unselectedLabelColor: const Color(0xFF94A3B8),
                      isScrollable: true,
                      tabs: const [
                        Tab(text: 'App Opened'),
                        Tab(text: 'Web Activity'),
                        Tab(text: 'Message Activity'),
                        Tab(text: 'Calls & Messages'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    final labels = ['app usage', 'web activity', 'social', 'telephony'];
                    final label = labels[_tabController.index];
                    final clearLabels = {
                      'app usage': 'App Opened',
                      'web activity': 'Web Activity',
                      'social': 'Message Activity',
                      'telephony': 'Calls & Messages',
                    };
                    final displayLabel = clearLabels[label] ?? label;
                    return Tooltip(
                      message: 'Clear $displayLabel history',
                      child: InkWell(
                        onTap: () => _clearHistory(context, label),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.delete_sweep_rounded, size: 16, color: Colors.redAccent),
                              const SizedBox(width: 6),
                              Text('Clear', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MonitoringUsageTab(deviceId: validId, isDark: widget.isDark, textColor: widget.textColor, cardColor: widget.cardColor),
                  _MonitoringWebTab(deviceId: validId, isDark: widget.isDark, textColor: widget.textColor, cardColor: widget.cardColor),
                  _MonitoringMessagesTab(deviceId: validId, isDark: widget.isDark, textColor: widget.textColor, cardColor: widget.cardColor, filterType: 'message'),
                  _MonitoringTelephonyTab(deviceId: validId, isDark: widget.isDark, textColor: widget.textColor, cardColor: widget.cardColor),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MonitoringUsageTab extends StatelessWidget {
  final String deviceId; final bool isDark; final Color textColor; final Color cardColor;
  const _MonitoringUsageTab({required this.deviceId, required this.isDark, required this.textColor, required this.cardColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Real-time Active App Header
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('devices').doc(deviceId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data?.data() == null) return const SizedBox.shrink();
            final data = snapshot.data!.data() as Map<String, dynamic>;
            final activeApp = data['activeApp'] ?? 'None';
            final lastActive = (data['lastActiveTime'] as Timestamp?)?.toDate();
            final isRecentlyActive = lastActive != null && DateTime.now().difference(lastActive).inMinutes < 5;

            return Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isRecentlyActive 
                    ? [const Color(0xFF6366F1), const Color(0xFF8B5CF6)] 
                    : [const Color(0xFF94A3B8), const Color(0xFF64748B)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: isRecentlyActive 
                  ? [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]
                  : [],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: Icon(isRecentlyActive ? Icons.bolt_rounded : Icons.pause_circle_outline_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isRecentlyActive ? 'LIVE NOW' : 'LAST SEEN ACTIVE', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white.withOpacity(0.8), letterSpacing: 1.5)),
                        const SizedBox(height: 4),
                        Text(activeApp, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                  if (isRecentlyActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                      child: Text('ACTIVE', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                ],
              ),
            );
          }
        ),

        // Session Timeline
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('devices')
                .doc(deviceId)
                .collection('activity')
                .where('type', isEqualTo: 'app_usage')
                .orderBy('timestamp', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: SelectableText('Error: ${snapshot.error}'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) return _buildEmptyState('No activity logs found.', Icons.history_rounded);

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final appName = (data['appName'] ?? data['packageName'] ?? 'Unknown').toString();
                  final duration = data['duration'] as num? ?? 0;
                  final ts = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
                  
                  String durationStr = '';
                  if (duration > 1000) {
                     final s = duration / 1000;
                     if (s < 60) durationStr = '${s.toInt()}s';
                     else if (s < 3600) durationStr = '${(s/60).toInt()}m';
                     else durationStr = '${(s/3600).toStringAsFixed(1)}h';
                  } else {
                     durationStr = '${duration.toInt()}m';
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: textColor.withOpacity(0.05)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.app_registration_rounded, color: Color(0xFF6366F1), size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(appName, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                              Text(DateFormat('h:mm a • MMM d').format(ts), style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8))),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(durationStr, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
                        ),
                      ],
                    ),
                  );
                },
              );
            }
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 48, color: const Color(0xFF94A3B8)), const SizedBox(height: 16), Text(text, style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))]));
  }
}

class _MonitoringWebTab extends StatelessWidget {
  final String deviceId; final bool isDark; final Color textColor; final Color cardColor;
  const _MonitoringWebTab({required this.deviceId, required this.isDark, required this.textColor, required this.cardColor});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('devices')
          .doc(deviceId)
          .collection('activity')
          .where('type', isEqualTo: 'url')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: SelectableText('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState('No browsing history captured.', Icons.history_edu_rounded);

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final url = data['content'] ?? '';
            final pkg = data['packageName'] ?? 'Browser';
            final appName = data['appName'] ?? pkg;
            final time = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
            final timeStr = DateFormat('MMM d, h:mm a').format(time);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF64748B).withOpacity(0.2))),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.public_rounded, color: Color(0xFF6366F1))),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(url, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('$appName • $timeStr', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 48, color: const Color(0xFF94A3B8)), const SizedBox(height: 16), Text(text, style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))]));
  }
}

class _MonitoringMessagesTab extends StatelessWidget {
  final String deviceId; final bool isDark; final Color textColor; final Color cardColor; final String filterType;
  const _MonitoringMessagesTab({required this.deviceId, required this.isDark, required this.textColor, required this.cardColor, required this.filterType});


  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('devices')
          .doc(deviceId)
          .collection('activity')
          .where('type', isEqualTo: filterType)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: SelectableText('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        
        // Pre-filter junk notifications before building the list
        final filteredDocs = docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final content = (d['content'] ?? d['subText'] ?? '').toString().trim();
          final subText = (d['subText'] ?? '').toString().trim();
          final senderStr = (d['sender'] ?? d['title'] ?? '').toString().trim();
          final textLower = '$content $subText $senderStr'.toLowerCase();
          if (textLower.contains('chat heads') || 
              textLower.contains('active chat') || 
              textLower.contains('running in background') ||
              textLower.contains('displaying over other apps') ||
              textLower.contains('chat head') ||
              textLower.contains('bubbles')) return false;
          if (content.isEmpty && subText.isEmpty) return false;
          return true;
        }).toList();
        
        if (filteredDocs.isEmpty) return _buildEmptyState('No messages yet.', Icons.message_outlined);

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final data = filteredDocs[index].data() as Map<String, dynamic>;
            
            final content = (data['content'] ?? data['subText'] ?? '').toString().trim();
            final subText = (data['subText'] ?? '').toString().trim();
            final rawSender = (data['sender'] ?? '').toString().trim();
            final titleStr = (data['title'] ?? '').toString().trim();
            // Default sender to "Me" when field is missing or empty
            final senderStr = rawSender.isNotEmpty ? rawSender : (titleStr.isNotEmpty ? titleStr : 'Me');
            final appName = (data['appName'] ?? data['packageName'] ?? 'App').toString();
            final isGroupMsg = data['isGroupConversation'] as bool? ?? false;

            final isMe = data['isMe'] as bool? ?? false;
            
            final msgTimeObj = data['msgTimestamp'] != null 
                ? DateTime.fromMillisecondsSinceEpoch(data['msgTimestamp'] as int) 
                : (data['timestamp'] as Timestamp?)?.toDate();
            final msgTimeStr = msgTimeObj != null ? DateFormat('MMM d, yyyy • h:mm a').format(msgTimeObj) : '';

            // UI Design for Flat Messages
            final bool out = isMe;
            final Color iconColor = out ? const Color(0xFF32B5E8) : const Color(0xFF00C853);
            final IconData icon = out ? Icons.call_made_rounded : Icons.call_received_rounded;
            
            // Determining the display title for reply/from:
            final displayPerson = titleStr.isNotEmpty && titleStr != appName 
                                    ? titleStr 
                                    : (senderStr != 'Me' ? senderStr : 'Unknown');

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E272E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: iconColor.withOpacity(0.3), width: 1),
                boxShadow: isDark 
                    ? [] 
                    : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(icon, color: iconColor, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                out ? "Outgoing (Reply to $displayPerson)" : "Incoming ($displayPerson)",
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: iconColor,
                                ),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        appName + (isGroupMsg && !out ? ' (Group)' : ''),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    content.isEmpty ? "🖼️ [Media/Attachment]" : content,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      msgTimeStr,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 48, color: const Color(0xFF94A3B8)), const SizedBox(height: 16), Text(text, style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))]));
  }
}


class _MonitoringTelephonyTab extends StatefulWidget {
  final String deviceId; final bool isDark; final Color textColor; final Color cardColor;
  const _MonitoringTelephonyTab({required this.deviceId, required this.isDark, required this.textColor, required this.cardColor});

  @override
  State<_MonitoringTelephonyTab> createState() => _MonitoringTelephonyTabState();
}

class _MonitoringTelephonyTabState extends State<_MonitoringTelephonyTab> with SingleTickerProviderStateMixin {
  late TabController _innerController;

  @override
  void initState() {
    super.initState();
    _innerController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _innerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _innerController,
          indicatorColor: const Color(0xFF6366F1),
          labelColor: const Color(0xFF6366F1),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Calls', icon: Icon(Icons.call_rounded, size: 18)),
            Tab(text: 'SMS Messages', icon: Icon(Icons.sms_rounded, size: 18)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _innerController,
            children: [
              _MonitoringMessagesTab(deviceId: widget.deviceId, isDark: widget.isDark, textColor: widget.textColor, cardColor: widget.cardColor, filterType: 'call'),
              _MonitoringMessagesTab(deviceId: widget.deviceId, isDark: widget.isDark, textColor: widget.textColor, cardColor: widget.cardColor, filterType: 'sms'),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE PROFILE VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _MobileProfileView extends StatefulWidget {
  final bool isDark;
  const _MobileProfileView({required this.isDark});
  @override State<_MobileProfileView> createState() => _MobileProfileViewState();
}

class _MobileProfileViewState extends State<_MobileProfileView> {
  bool _saving = false;
  bool _editingPhoto = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _photoUrlCtrl;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameCtrl = TextEditingController(text: user?.displayName ?? '');
    _emailCtrl = TextEditingController(text: user?.email ?? '');
    _phoneCtrl = TextEditingController(text: user?.phoneNumber ?? '');
    _photoUrlCtrl = TextEditingController(text: user?.photoURL ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose(); _photoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.updateDisplayName(_nameCtrl.text.trim());
      final photoUrl = _photoUrlCtrl.text.trim();
      if (photoUrl.isNotEmpty) await user?.updatePhotoURL(photoUrl);
      final uid = user?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'displayName': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          if (photoUrl.isNotEmpty) 'photoURL': photoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      setState(() => _editingPhoto = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated!'), backgroundColor: Color(0xFF22C55E)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF060D1F) : const Color(0xFFF8FAFC);
    final cardBg = widget.isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor = widget.isDark ? Colors.white54 : const Color(0xFF64748B);
    final border = const Color(0xFF6366F1).withOpacity(0.25);
    final user = FirebaseAuth.instance.currentUser;
    final initial = (_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0] : (user?.email?[0] ?? 'P')).toUpperCase();

    return StreamBuilder<DocumentSnapshot>(
      stream: user != null ? FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots() : const Stream.empty(),
      builder: (context, snap) {
        final extraData = snap.data?.data() as Map<String, dynamic>? ?? {};
        final role = (extraData['role'] ?? 'parent').toString();
        final plan = (extraData['plan'] ?? extraData['subscription'] ?? 'Free').toString();
        final joined = extraData['createdAt'] as Timestamp?;
        final joinedStr = joined != null ? DateFormat('MMM d, yyyy').format(joined.toDate()) : 'N/A';

        final storedPhotoUrl = extraData['photoURL']?.toString() ?? user?.photoURL ?? '';
        final effectivePhotoUrl = _photoUrlCtrl.text.trim().isNotEmpty ? _photoUrlCtrl.text.trim() : storedPhotoUrl;

        return Container(
          color: bg,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Avatar + info
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: border)),
                child: Column(children: [
                Row(children: [
                  Stack(alignment: Alignment.bottomRight, children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: effectivePhotoUrl.isEmpty ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                        image: effectivePhotoUrl.isNotEmpty ? DecorationImage(image: NetworkImage(effectivePhotoUrl), fit: BoxFit.cover) : null,
                      ),
                      child: effectivePhotoUrl.isEmpty ? Center(child: Text(initial, style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white))) : null,
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _editingPhoto = !_editingPhoto),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Color(0xFF6366F1), shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                  ]),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user?.displayName ?? user?.email?.split('@').first ?? 'Parent', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
                    const SizedBox(height: 4),
                    Text(user?.email ?? '', style: GoogleFonts.outfit(fontSize: 12, color: subColor)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text(role.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF6366F1)))),
                      const SizedBox(width: 6),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(plan, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF22C55E)))),
                    ]),
                  ])),
                ]),
                if (_editingPhoto) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _photoUrlCtrl,
                    style: GoogleFonts.outfit(fontSize: 12, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Paste image URL to set photo…',
                      hintStyle: GoogleFonts.outfit(fontSize: 12, color: subColor),
                      prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF6366F1), size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      suffixIcon: _photoUrlCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.check_rounded, size: 14, color: Color(0xFF22C55E)), onPressed: () => setState(() => _editingPhoto = false)) : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.4))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.25))),
                      filled: true, fillColor: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                ]),
              ),
              const SizedBox(height: 16),

              // Stats row
              Row(children: [
                _ProfileStat(label: 'Member Since', value: joinedStr, icon: Icons.calendar_today_rounded, isDark: widget.isDark),
                const SizedBox(width: 10),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseService.instance.streamAdminDevices(),
                  builder: (context, dSnap) {
                    final count = dSnap.data?.docs.length ?? 0;
                    return _ProfileStat(label: 'Devices', value: '$count', icon: Icons.phone_android_rounded, isDark: widget.isDark);
                  },
                ),
              ]),
              const SizedBox(height: 16),

              // Edit form
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Edit Profile', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: textColor)),
                  const SizedBox(height: 14),
                  _ProfileField(label: 'Full Name', controller: _nameCtrl, icon: Icons.person_rounded, isDark: widget.isDark),
                  const SizedBox(height: 10),
                  _ProfileField(label: 'Email', controller: _emailCtrl, icon: Icons.email_rounded, isDark: widget.isDark, readOnly: true),
                  const SizedBox(height: 10),
                  _ProfileField(label: 'Phone Number', controller: _phoneCtrl, icon: Icons.phone_rounded, isDark: widget.isDark),
                  const SizedBox(height: 10),
                  _ProfileField(label: 'Photo URL (optional)', controller: _photoUrlCtrl, icon: Icons.image_rounded, isDark: widget.isDark),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Save Changes', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // Account actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Account', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: textColor)),
                  const SizedBox(height: 12),
                  ListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_rounded, color: Color(0xFF6366F1), size: 22),
                    title: Text('Change Password', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                    onTap: () {
                      if (user?.email != null) {
                        FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent!'), backgroundColor: Color(0xFF6366F1)));
                      }
                    },
                  ),
                  Divider(color: border, height: 1),
                  ListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 22),
                    title: Text('Sign Out', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFFEF4444))),
                    onTap: () => FirebaseAuth.instance.signOut(),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String label, value; final IconData icon; final bool isDark;
  const _ProfileStat({required this.label, required this.value, required this.icon, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF0F1A35) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 22),
        const SizedBox(height: 6),
        Text(value, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: textColor)),
        Text(label, style: GoogleFonts.outfit(fontSize: 11, color: subColor, fontWeight: FontWeight.w500)),
      ]),
    ));
  }
}

class _ProfileField extends StatelessWidget {
  final String label; final TextEditingController controller; final IconData icon; final bool isDark; final bool readOnly;
  const _ProfileField({required this.label, required this.controller, required this.icon, required this.isDark, this.readOnly = false});
  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: subColor, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(
        controller: controller, readOnly: readOnly,
        style: GoogleFonts.outfit(fontSize: 13, color: readOnly ? subColor : textColor),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xFF6366F1), size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          filled: true, fillColor: isDark ? Colors.white.withOpacity(readOnly ? 0.04 : 0.07) : (readOnly ? const Color(0xFFF1F5F9) : Colors.white),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.25))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DESKTOP PROFILE VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileView extends StatefulWidget {
  final bool isDark; final Color cardColor, textColor, borderColor;
  const _ProfileView({required this.isDark, required this.cardColor, required this.textColor, required this.borderColor});
  @override State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  bool _saving = false;
  bool _editingPhoto = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _photoUrlCtrl;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameCtrl = TextEditingController(text: user?.displayName ?? '');
    _emailCtrl = TextEditingController(text: user?.email ?? '');
    _phoneCtrl = TextEditingController(text: user?.phoneNumber ?? '');
    _bioCtrl = TextEditingController();
    _photoUrlCtrl = TextEditingController(text: user?.photoURL ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    _bioCtrl.dispose(); _photoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.updateDisplayName(_nameCtrl.text.trim());
      final photoUrl = _photoUrlCtrl.text.trim();
      if (photoUrl.isNotEmpty) await user?.updatePhotoURL(photoUrl);
      final uid = user?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'displayName': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'bio': _bioCtrl.text.trim(),
          if (photoUrl.isNotEmpty) 'photoURL': photoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      setState(() => _editingPhoto = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated!'), backgroundColor: Color(0xFF22C55E)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final initial = (_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0] : (user?.email?[0] ?? 'P')).toUpperCase();

    return StreamBuilder<DocumentSnapshot>(
      stream: user != null ? FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots() : const Stream.empty(),
      builder: (context, snap) {
        final extraData = snap.data?.data() as Map<String, dynamic>? ?? {};
        final role = (extraData['role'] ?? 'parent').toString();
        final plan = (extraData['plan'] ?? extraData['subscription'] ?? 'Free').toString();
        final joined = extraData['createdAt'] as Timestamp?;
        final joinedStr = joined != null ? DateFormat('MMM d, yyyy').format(joined.toDate()) : 'N/A';
        if (_bioCtrl.text.isEmpty && extraData['bio'] != null) _bioCtrl.text = extraData['bio'].toString();
        final storedPhotoUrl = extraData['photoURL']?.toString() ?? user?.photoURL ?? '';
        final effectivePhotoUrl = _photoUrlCtrl.text.trim().isNotEmpty ? _photoUrlCtrl.text.trim() : storedPhotoUrl;

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My Profile', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w900, color: widget.textColor)),
            const SizedBox(height: 6),
            Text('Manage your account information and preferences.', style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF94A3B8))),
            const SizedBox(height: 28),

            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Left: avatar + stats
              SizedBox(width: 260, child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: widget.borderColor)),
                  child: Column(children: [
                    Stack(alignment: Alignment.bottomRight, children: [
                      Container(
                        width: 88, height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: effectivePhotoUrl.isEmpty ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]) : null,
                          image: effectivePhotoUrl.isNotEmpty ? DecorationImage(image: NetworkImage(effectivePhotoUrl), fit: BoxFit.cover) : null,
                        ),
                        child: effectivePhotoUrl.isEmpty ? Center(child: Text(initial, style: GoogleFonts.outfit(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white))) : null,
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _editingPhoto = !_editingPhoto),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Color(0xFF6366F1), shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ]),
                    if (_editingPhoto) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _photoUrlCtrl,
                        style: GoogleFonts.outfit(fontSize: 11, color: widget.textColor),
                        decoration: InputDecoration(
                          hintText: 'Paste image URL…',
                          hintStyle: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          suffixIcon: _photoUrlCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.check_rounded, size: 14, color: Color(0xFF22C55E)), onPressed: () => setState(() => _editingPhoto = false)) : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.4))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.25))),
                          filled: true, fillColor: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(user?.displayName ?? user?.email?.split('@').first ?? 'Parent', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: widget.textColor), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(user?.email ?? '', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Text(role.toUpperCase(), style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF6366F1)))),
                      const SizedBox(width: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(plan, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF22C55E)))),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: widget.borderColor)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Account Details', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: widget.textColor)),
                    const SizedBox(height: 12),
                    _InfoRow(icon: Icons.calendar_today_rounded, label: 'Member Since', value: joinedStr, isDark: widget.isDark),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseService.instance.streamAdminDevices(),
                      builder: (context, dSnap) => _InfoRow(icon: Icons.phone_android_rounded, label: 'Devices', value: '${dSnap.data?.docs.length ?? 0}', isDark: widget.isDark),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (user?.email != null) {
                          FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent!'), backgroundColor: Color(0xFF6366F1)));
                        }
                      },
                      icon: const Icon(Icons.lock_reset_rounded, size: 16),
                      label: Text('Reset Password', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), minimumSize: const Size(double.infinity, 40)),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: Text('Sign Out', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), minimumSize: const Size(double.infinity, 40)),
                    ),
                  ]),
                ),
              ])),
              const SizedBox(width: 24),

              // Right: edit form
              Expanded(child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: widget.borderColor)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Edit Information', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: widget.textColor)),
                  const SizedBox(height: 6),
                  Text('Changes are saved to your account.', style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8))),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(child: _DesktopProfileField(label: 'Full Name', controller: _nameCtrl, icon: Icons.person_rounded, isDark: widget.isDark)),
                    const SizedBox(width: 16),
                    Expanded(child: _DesktopProfileField(label: 'Email Address', controller: _emailCtrl, icon: Icons.email_rounded, isDark: widget.isDark, readOnly: true)),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _DesktopProfileField(label: 'Phone Number', controller: _phoneCtrl, icon: Icons.phone_rounded, isDark: widget.isDark)),
                    const SizedBox(width: 16),
                    Expanded(child: _DesktopProfileField(label: 'Bio / Notes', controller: _bioCtrl, icon: Icons.notes_rounded, isDark: widget.isDark, maxLines: 1)),
                  ]),
                  const SizedBox(height: 16),
                  _DesktopProfileField(label: 'Photo URL (paste image link)', controller: _photoUrlCtrl, icon: Icons.image_rounded, isDark: widget.isDark),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
                      child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Save Changes', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ]),
              )),
            ]),
          ]),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label, value; final bool isDark;
  const _InfoRow({required this.icon, required this.label, required this.value, required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: const Color(0xFF6366F1)),
      const SizedBox(width: 8),
      Text('$label: ', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
      Expanded(child: Text(value, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
    ]);
  }
}

class _DesktopProfileField extends StatelessWidget {
  final String label; final TextEditingController controller; final IconData icon; final bool isDark; final bool readOnly; final int maxLines;
  const _DesktopProfileField({required this.label, required this.controller, required this.icon, required this.isDark, this.readOnly = false, this.maxLines = 1});
  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: subColor, letterSpacing: 1)),
      const SizedBox(height: 8),
      TextField(
        controller: controller, readOnly: readOnly, maxLines: maxLines,
        style: GoogleFonts.outfit(fontSize: 14, color: readOnly ? subColor : textColor),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xFF6366F1), size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          filled: true, fillColor: isDark ? Colors.white.withOpacity(readOnly ? 0.04 : 0.07) : (readOnly ? const Color(0xFFF1F5F9) : Colors.white),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.25))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.25))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
        ),
      ),
    ]);
  }
}
