// lib/dashboard/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart' hide Path;
import 'package:flutter/scheduler.dart';
import 'dart:ui' as ui;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:heroicons/heroicons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../shared/firebase_service.dart';
enum _DashboardMenu { dashboard, devices, apps, schedules, location, monitoring, reports, subscriptions, settings, users }

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
      return Dialog(
        backgroundColor: cardColor,
        elevation: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('Pair New Device', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: textColor)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context), 
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 200,
                  foregroundColor: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 32),
              Text('6-DIGIT PAIRING PIN', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2)),
                ),
                child: Text(
                  pin,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(fontSize: 36, fontWeight: FontWeight.w900, color: const Color(0xFF6366F1), letterSpacing: 8),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Scan the QR code or enter the secret PIN\non the child device to start monitoring.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: textColor.withOpacity(0.05),
                  ),
                  child: Text('Close', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textColor)),
                ),
              ),
            ],
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
  bool _isDark = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
      builder: (context, userSnapshot) {
        String userRole = 'parent';
        if (userSnapshot.hasData && userSnapshot.data?.data() != null) {
          final data = userSnapshot.data!.data() as Map<String, dynamic>;
          userRole = data['role'] ?? 'parent';
        }
        
        final bool isMobile = MediaQuery.of(context).size.width <= 1024;
        final bgColor = _isDark ? const Color(0xFF0D0D10) : const Color(0xFFF8FAFC);
        final cardColor = _isDark ? const Color(0xFF18181B) : Colors.white;
        final textColor = _isDark ? Colors.white : const Color(0xFF1E293B);
        final borderColor = const Color(0xFF64748B);

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: bgColor,
          drawer: isMobile ? Drawer(width: 280, backgroundColor: cardColor, child: _Sidebar(selectedMenu: _selectedMenu, onMenuSelected: (menu) { setState(() => _selectedMenu = menu); Navigator.pop(context); }, isCollapsed: false, isDark: _isDark, userRole: userRole)) : null,
          body: Row(
            children: [
              if (!isMobile) _Sidebar(selectedMenu: _selectedMenu, onMenuSelected: (menu) => setState(() => _selectedMenu = menu), isCollapsed: !_isSidebarOpen, isDark: _isDark, userRole: userRole),
              Expanded(
                child: Column(
                  children: [
                    _Header(title: _selectedMenu.name.toUpperCase(), onMenuPressed: () { if (isMobile) { _scaffoldKey.currentState?.openDrawer(); } else { setState(() => _isSidebarOpen = !_isSidebarOpen); } }, isDark: _isDark, onThemeToggle: () => setState(() => _isDark = !_isDark), isMobile: isMobile),
                    Expanded(child: Padding(padding: EdgeInsets.all(isMobile ? 20 : 32), child: _buildContent(textColor, cardColor, borderColor, isMobile, userRole))),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildContent(Color textColor, Color cardColor, Color borderColor, bool isMobile, String userRole) {
    switch (_selectedMenu) {
      case _DashboardMenu.dashboard: return _DashboardOverview(isDark: _isDark, isMobile: isMobile, userRole: userRole);
      case _DashboardMenu.devices: return SingleChildScrollView(child: _DevicesList(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, isMobile: isMobile, userRole: userRole));
      case _DashboardMenu.apps: return SingleChildScrollView(child: _AppControls(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.schedules: return SingleChildScrollView(child: _SchedulesView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.location: return _LocationView(isDark: _isDark, textColor: textColor);
      case _DashboardMenu.monitoring: return _MonitoringView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, isMobile: isMobile);
      case _DashboardMenu.reports: return SingleChildScrollView(child: _ReportsView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.subscriptions: return SingleChildScrollView(child: _SubscriptionView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, userRole: userRole));
      case _DashboardMenu.settings: return SingleChildScrollView(child: _SettingsView(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor));
      case _DashboardMenu.users: return SingleChildScrollView(child: _UsersList(isDark: _isDark, cardColor: cardColor, textColor: textColor, borderColor: borderColor, isMobile: isMobile));
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
          _buildSidebarItem(_DashboardMenu.location, 'Location Tracking', HeroIcons.mapPin),
          _buildSidebarItem(_DashboardMenu.monitoring, 'Child Monitoring', HeroIcons.magnifyingGlassCircle),
          _buildSidebarItem(_DashboardMenu.reports, 'Activity Reports', HeroIcons.chartBar),
          _buildSidebarItem(_DashboardMenu.subscriptions, 'Subscription', HeroIcons.creditCard),
          _buildSidebarItem(_DashboardMenu.settings, 'Settings', HeroIcons.cog6Tooth),
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
  const _Header({required this.title, required this.onMenuPressed, required this.isDark, required this.onThemeToggle, required this.isMobile});
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
            if (snapshot.hasData && snapshot.data?.data() != null) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              plan = (data['plan'] ?? 'FREE').toString().toUpperCase();
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), 
              decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), 
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_rounded, size: 16, color: Color(0xFF6366F1)), 
                  if (!isMobile) ...[
                    const SizedBox(width: 6), 
                    Text(plan, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF6366F1)))
                  ]
                ]
              )
            );
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
      _StatCard(title: 'Blocked Apps', value: blocked.toString(), icon: HeroIcons.shieldExclamation, color: const Color(0xFFF59E0B), isDark: isDark),
      _StatCard(title: 'Hidden Apps', value: hidden.toString(), icon: HeroIcons.eyeSlash, color: const Color(0xFF8B5CF6), isDark: isDark),
      _StatCard(title: 'Total Apps', value: totalApps.toString(), icon: HeroIcons.squaresPlus, color: const Color(0xFFEC4899), isDark: isDark),
    ]; 
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
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.smartphone_rounded, color: Color(0xFF6366F1), size: 22)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(deviceId, style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18, color: widget.textColor), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 2), Text('Status: ${device['status'] ?? 'offline'}', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12))])),
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
              _buildMiniActionButton(icon: Icons.message_rounded, color: const Color(0xFFF59E0B), onTap: () => showDialog(context: context, builder: (_) => AlertDialog(backgroundColor: widget.cardColor, title: const Text('Latest Messages'), content: Text(device['lastMessage'] ?? 'No recent messages exist on this device.')))),
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
  void _removeDevice(String deviceId) async { final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(backgroundColor: widget.cardColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('Remove Device?'), content: const Text('This will unlink the device and stop monitoring.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.redAccent)))])); if (confirm == true) await FirebaseFirestore.instance.collection('devices').doc(deviceId).delete(); }
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
        
        final filteredApps = apps.where((app) {
          final d = app as Map<String, dynamic>;
          final pkg = (d['packageName'] ?? '').toString();
          final name = (d['appName'] ?? d['name'] ?? d['label'] ?? '').toString().toLowerCase();
          
          // Apply search filter
          final query = _searchQuery.toLowerCase();
          final matchesSearch = name.contains(query) || pkg.toLowerCase().contains(query);
          if (!matchesSearch) return false;
          
          // Apply category filter
          if (_filterMode == 'blocked') return blockedApps.contains(pkg);
          if (_filterMode == 'hidden') return hiddenApps.contains(pkg);
          if (_filterMode == 'allowed') return !blockedApps.contains(pkg) && !hiddenApps.contains(pkg);
          
          return true; // 'all' mode
        }).toList();

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
                      startCtrl.text = DateFormat('h:mm a').format(startDt);
                      endCtrl.text = DateFormat('h:mm a').format(endDt);
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
            onPressed: () {
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
          if (schedule != null)
            IconButton(
              onPressed: () => _showRestrictionDialog(context, pkg, appName),
              icon: const Icon(Icons.edit_note_rounded, size: 22, color: Color(0xFF6366F1)),
              tooltip: 'Edit Active Rule',
            ),
          PopupMenuButton<String>(
            icon: Icon(
              isBlocked ? Icons.block_rounded : (isHidden ? Icons.visibility_off_rounded : Icons.more_vert_rounded),
              size: 18,
              color: isBlocked ? Colors.red : (isHidden ? Colors.purple : const Color(0xFF94A3B8)),
            ),
            onSelected: (val) {
              if (val == 'setup' || val == 'edit') {
                _showRestrictionDialog(context, pkg, appName);
                return;
              }
              final newBlocked = List<String>.from(blockedApps)..remove(pkg);
              final newHidden = List<String>.from(hiddenApps)..remove(pkg);
              final newSchedules = Map<String, dynamic>.from(appSchedules);
              
              if (val == 'block') {
                if (blockedApps.length >= blockedLimit) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Blocked apps limit reached ($blockedLimit)'), backgroundColor: Colors.redAccent));
                  return;
                }
                newBlocked.add(pkg);
                newSchedules[pkg] = { 'start': '12:00 AM', 'end': '12:00 AM', 'alwaysBlocked': true };
              }
              if (val == 'hide') {
                if (hiddenApps.length >= hiddenLimit) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hidden apps limit reached ($hiddenLimit)'), backgroundColor: Colors.redAccent));
                  return;
                }
                newHidden.add(pkg);
              }
              if (val == 'allow') {
                newSchedules.remove(pkg);
              }

              FirebaseFirestore.instance.collection('devices').doc(deviceId).update({
                'blockedApps': newBlocked, 'hiddenApps': newHidden, 'appSchedules': newSchedules,
              });
            },
            itemBuilder: (c) => [
              PopupMenuItem(
                value: schedule != null ? 'edit' : 'setup', 
                child: Row(children: [const Icon(Icons.timer_rounded, size: 16), const SizedBox(width: 8), Text(schedule != null ? 'Edit Rules' : 'Setup Rules')])
              ),
              const PopupMenuItem(value: 'allow', child: Text('Allow All Access')),
              const PopupMenuItem(value: 'block', child: Text('Block Instantly')),
              const PopupMenuItem(value: 'hide', child: Text('Hide Icon')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SchedulesView extends StatelessWidget {
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
            allRules.add({
              'deviceId': deviceId,
              'type': 'Device Lock',
              'rule': '${s['start']} - ${s['end']}',
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
            allRules.add({
              'deviceId': deviceId,
              'type': 'App Restriction',
              'rule': always ? 'Always Blocked' : '${s['start']} - ${s['end']}',
              'target': pkg.split('.').last.toUpperCase(),
              'pkgName': pkg,
              'icon': Icons.apps_rounded,
              'color': const Color(0xFF6366F1),
            });
          } );
        }

        if (allRules.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const HeroIcon(HeroIcons.calendar, size: 64, color: Color(0xFFCBD5E1)), 
                const SizedBox(height: 16), 
                Text('No active rules found', style: GoogleFonts.outfit(fontSize: 18, color: textColor))
              ]
            )
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active Time Rules', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
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
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF64748B), width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: rule['color'].withOpacity(0.1), shape: BoxShape.circle),
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
                            Text(rule['target'], style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
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
                          // DELETE LOGIC
                          if (rule['type'] == 'Device Lock') {
                            FirebaseFirestore.instance.collection('devices').doc(rule['deviceId']).get().then((doc) {
                              if (!doc.exists) return;
                              final data = doc.data() as Map<String, dynamic>;
                              final list = List<Map<String, dynamic>>.from(data['lockSchedules'] ?? []);
                              list.removeWhere((s) => '${s['start']} - ${s['end']}' == rule['rule']);
                              FirebaseFirestore.instance.collection('devices').doc(rule['deviceId']).update({'lockSchedules': list});
                            });
                          } else {
                            // App Restriction
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
                        onPressed: () {
                          // EDIT placeholder: In a full implementation, this would trigger the same dialogs as the cards.
                        },
                        icon: const Icon(Icons.edit_note_rounded, size: 22, color: Color(0xFF94A3B8)),
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
  const _LocationView({required this.isDark, required this.textColor});

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
  bool _isLoading = false;

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
    super.dispose();
  }

  @override 
  Widget build(BuildContext context) { 
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.streamAdminDevices(),
      builder: (context, snapshot) {
        final devices = snapshot.data?.docs ?? [];
        if (_selectedDeviceId == null && devices.isNotEmpty) {
          _selectedDeviceId = devices.first.id;
          // Initial load
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadDeviceSettings(_selectedDeviceId!, devices);
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Settings', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: widget.textColor)),
            const SizedBox(height: 8),
            Text('Manage your account, preferences, and system security.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
            const SizedBox(height: 32),
            
            _buildSettingsSection('DEVICE LOCK SCREEN SETTINGS', [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TARGET DEVICE', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedDeviceId,
                          isExpanded: true,
                          dropdownColor: widget.cardColor,
                          items: devices.map((d) => DropdownMenuItem(value: d.id, child: Text(d.id, style: GoogleFonts.outfit(color: widget.textColor)))).toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() => _selectedDeviceId = val);
                            _loadDeviceSettings(val, devices);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    Text('CORE MESSAGING', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF6366F1), letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    _buildInputField('LOCK SCREEN HEADLINE', 'e.g. Parental Control Active', _lockHeadlineCtrl),
                    const SizedBox(height: 16),
                    _buildInputField('LOCK SCREEN TITLE', 'e.g. Mother\'s To-Do List', _taskTitleCtrl),
                    const SizedBox(height: 16),
                    _buildInputField('LOCK SCREEN TASKS (One per line)', 'e.g. Brush teeth\nStudy for 1 hour', _taskListCtrl, maxLines: 4),
                    const SizedBox(height: 16),
                    _buildInputField('LOCK SCREEN FALLBACK MESSAGE', 'Shown when task list is empty', _lockMsgCtrl, maxLines: 2),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 24),

            _buildSettingsSection('APP RESTRICTION SETTINGS', [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CORE MESSAGING', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF6366F1), letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    _buildInputField('APP RESTRICTED HEADLINE', 'e.g. App Restricted', _restHeadlineCtrl),
                    const SizedBox(height: 16),
                    _buildInputField('APP RESTRICTED FALLBACK MESSAGE', 'Shown when task list is empty', _restMsgCtrl, maxLines: 2),
                    const SizedBox(height: 24),
                    
                    Text('RESTRICTED TASK LIST', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF6366F1), letterSpacing: 1.5)),
                    const SizedBox(height: 16),
                    _buildInputField('LIST OF TASKS TO SHOW (One per line)', 'e.g. Just for today, sorry\nAsk your parent first', _warningListCtrl, maxLines: 4),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveSettings,
                icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 18),
                label: Text(_isLoading ? 'SAVING CHANGES...' : 'SAVE ALL SETTINGS', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 8,
                  shadowColor: const Color(0xFF6366F1).withOpacity(0.5),
                ),
              ),
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
      if ((doc.data())['subscriptionActive'] != isActive) {
         doc.reference.update({'subscriptionActive': isActive});
      }
    }
  }

  void _initializeDefaultPlans() async {
    final batch = FirebaseFirestore.instance.batch();
    final free = FirebaseFirestore.instance.collection('plans').doc('free');
    final starter = FirebaseFirestore.instance.collection('plans').doc('starter');
    final pro = FirebaseFirestore.instance.collection('plans').doc('pro');

    batch.set(free, {'name': 'Free', 'price': 0, 'deviceLimit': 1, 'blockedAppsLimit': 5, 'hiddenAppsLimit': 2, 'features': ['Basic Monitoring', 'Manual Lock', 'Standard Reports'], 'color': '0xFF94A3B8'});
    batch.set(starter, {'name': 'Starter', 'price': 10, 'deviceLimit': 3, 'blockedAppsLimit': 20, 'hiddenAppsLimit': 10, 'features': ['Real-time Tracking', 'App Blocking', 'Geofencing'], 'color': '0xFF10B981'});
    batch.set(pro, {'name': 'Pro', 'price': 25, 'deviceLimit': 10, 'blockedAppsLimit': 999, 'hiddenAppsLimit': 999, 'features': ['Priority Support', 'Usage Timeline', 'Unlimited History'], 'color': '0xFF6366F1'});
    
    await batch.commit();
  }

  Widget _buildPlanCard(BuildContext context, String id, String name, String price, String limit, List<String> features, bool isActive, bool isCurrent, Color color, {String blockedLimit = "0", String hiddenLimit = "0", double thisPrice = 0, double currentPrice = 0}) {
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
                       'blockedAppsLimit': blockedLimit, 'hiddenAppsLimit': hiddenLimit
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
            Text('/mo', style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF94A3B8))),
          ]),
          const SizedBox(height: 16),
          Text(limit, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text('$blockedLimit Blocked Apps allowed', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: color.withOpacity(0.8))),
          Text('$hiddenLimit Hidden Apps allowed', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: color.withOpacity(0.8))),
          const SizedBox(height: 24),
          ...features.map((f) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Icon(Icons.check_circle_rounded, size: 16, color: color), const SizedBox(width: 10), Expanded(child: Text(f, style: GoogleFonts.outfit(fontSize: 13, color: textColor)))]))).toList(),
          const SizedBox(height: 32),
          if (userRole != 'super_admin')
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
    final nameCtrl = TextEditingController(text: existing?['name']);
    final priceCtrl = TextEditingController(text: existing?['price']);
    final limitCtrl = TextEditingController(text: existing?['deviceLimit']);
    final blockedCtrl = TextEditingController(text: (existing?['blockedAppsLimit'] ?? '5').toString());
    final hiddenCtrl = TextEditingController(text: (existing?['hiddenAppsLimit'] ?? '2').toString());
    final List<TextEditingController> featureCtrls = (existing?['features'] as List? ?? [''])
        .map((f) => TextEditingController(text: f.toString())).toList();
    final colorCtrl = TextEditingController(text: existing?['color'] ?? '0xFF6366F1');

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
              children: [
                _buildField('Plan Name', nameCtrl),
                _buildField(r'Monthly Price ($)', priceCtrl, isNum: true),
                _buildField('Max Devices', limitCtrl, isNum: true),
                _buildField('Max Blocked Apps', blockedCtrl, isNum: true),
                _buildField('Max Hidden Apps', hiddenCtrl, isNum: true),
                
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('FEATURES', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => setDialogState(() => featureCtrls.add(TextEditingController())),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF6366F1)),
                    ),
                  ],
                ),
                ...featureCtrls.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var ctrl = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: _buildField('Feature ${idx + 1}', ctrl)),
                        IconButton(
                          onPressed: () => setDialogState(() => featureCtrls.removeAt(idx)),
                          icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: Colors.redAccent),
                        ),
                      ],
                    ),
                  );
                }).toList(),

                _buildField('Hex Color (e.g. 0xFF6366F1)', colorCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
            ElevatedButton(
              onPressed: () async {
                final planData = {
                  'name': nameCtrl.text.trim(),
                  'price': double.tryParse(priceCtrl.text) ?? 0.0,
                  'deviceLimit': int.tryParse(limitCtrl.text) ?? 1,
                  'blockedAppsLimit': int.tryParse(blockedCtrl.text) ?? 0,
                  'hiddenAppsLimit': int.tryParse(hiddenCtrl.text) ?? 0,
                  'features': featureCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
                  'color': colorCtrl.text.trim(),
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
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Upgrade to ${planName.toUpperCase()}', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textColor)),
        content: Text('Confirm selection of the ${planName.toUpperCase()} plan. This is a mock payment for testing.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('users').doc(uid).update({
                'plan': planId,
                'expiryDate': DateTime.now().add(const Duration(days: 30)),
              });
              
              final devices = await FirebaseFirestore.instance.collection('devices').where('parentUid', isEqualTo: uid).get();
              for (var doc in devices.docs) {
                doc.reference.update({'subscriptionActive': true});
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully upgraded to $planName!'), backgroundColor: const Color(0xFF10B981)));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Confirm & Pay', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
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
                    Text('Child Monitoring', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: widget.textColor)),
                    const SizedBox(height: 4),
                    Text('Live monitoring of app usage, web history, and conversations.', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14)),
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
                        Tab(text: 'Social Messages'),
                        Tab(text: 'Calls & SMS'),
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
                      'social': 'Social Messages',
                      'telephony': 'Calls & SMS',
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
        if (docs.isEmpty) return _buildEmptyState('No messages intercepted yet.', Icons.message_outlined);

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            
            final content = (data['content'] ?? data['subText'] ?? '').toString().trim();
            final subText = (data['subText'] ?? '').toString().trim();
            final senderStr = (data['sender'] ?? data['title'] ?? 'Unknown').toString().trim();
            final titleStr = (data['title'] ?? '').toString().trim();
            final appName = (data['appName'] ?? data['packageName'] ?? 'App').toString();
            final isGroupMsg = data['isGroupConversation'] as bool? ?? false;
            
            final textLower = '$content $subText $senderStr'.toLowerCase();
            
            // Pure junk filter
            if (textLower.contains('chat heads') || 
                textLower.contains('active chat') || 
                textLower.contains('running in background') ||
                textLower.contains('displaying over other apps')) {
              return const SizedBox.shrink();
            }
            if (content.isEmpty && subText.isEmpty) return const SizedBox.shrink();

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
