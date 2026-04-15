// lib/dashboard/main_web.dart
// Parent PWA Dashboard entry point
// Build: flutter build web --target lib/dashboard/main_web.dart
// Run: flutter run --target lib/dashboard/main_web.dart -d chrome

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/firebase_service.dart';
import '../firebase_options.dart';
import 'dashboard_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Disable runtime fetching to avoid CORS and long loading issues on Web.
  // The correct fonts are already loaded via index.html.
  GoogleFonts.config.allowRuntimeFetching = false;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    runApp(const ParentDashboardApp());
  } catch (e) {
    runApp(_StartupErrorApp(error: e.toString()));
  }
}

class ParentDashboardApp extends StatelessWidget {
  const ParentDashboardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppLocker Admin Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1), primary: const Color(0xFF6366F1), secondary: const Color(0xFFA855F7)),
        useMaterial3: true,
        textTheme: GoogleFonts.outfitTextTheme(),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (!snapshot.hasData) return const LoginScreen();
          return const DashboardScreen();
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false; String? _errorMessage;

  @override void dispose() { _emailController.dispose(); _passwordController.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) { setState(() => _errorMessage = 'Please fill in all fields'); return; }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await FirebaseService.instance.signIn(email: _emailController.text.trim(), password: _passwordController.text);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString().contains('] ') ? e.toString().split('] ').last : e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _socialLogin(String type) async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      if (type == 'google') {
        await FirebaseService.instance.signInWithGoogle();
      } else {
        await FirebaseService.instance.signInWithFacebook();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Social login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Stack(children: [
        Positioned(top: -100, left: -100, child: Container(width: 400, height: 400, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFB1A2E4).withOpacity(0.15), const Color(0xFFB1A2E4).withOpacity(0)]))).animate().fadeIn(duration: 1.seconds).scale()),
        Positioned(bottom: -50, right: -50, child: Container(width: 500, height: 500, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFB2D4F3).withOpacity(0.15), const Color(0xFFB2D4F3).withOpacity(0)]))).animate().fadeIn(duration: 1.2.seconds, delay: 200.ms)),
        Center(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 12))]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Center(child: _buildLogo()), const SizedBox(height: 32),
                      Text('Email Address', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
                      const SizedBox(height: 8),
                      TextField(controller: _emailController, decoration: InputDecoration(hintText: 'name@company.com', hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14), prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18, color: Color(0xFF64748B)), filled: true, fillColor: const Color(0xFFF8FAFC), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)))),
                      const SizedBox(height: 16),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Password', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF475569))), TextButton(onPressed: () {}, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap), child: Text('Forgot password?', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF6366F1))))]),
                      const SizedBox(height: 8),
                      TextField(controller: _passwordController, obscureText: true, decoration: InputDecoration(hintText: 'Enter your password', hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14), prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF64748B)), filled: true, fillColor: const Color(0xFFF8FAFC), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)))),
                      const SizedBox(height: 20),
                      if (_errorMessage != null) ...[Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500)), const SizedBox(height: 16)],
                      _buildSignInButton().animate().fadeIn().scale(), const SizedBox(height: 24),
                      Row(children: [const Expanded(child: Divider(color: Color(0xFFF1F5F9))), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('Or login with', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)))), const Expanded(child: Divider(color: Color(0xFFF1F5F9)))]),
                      const SizedBox(height: 20),
                      _buildSocialButtons(), const SizedBox(height: 24),
                      Center(child: Wrap(alignment: WrapAlignment.center, children: [Text("Don't have an account? ", style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF64748B))), MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: () {}, child: Text("Create free account", style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF6366F1)))))]))
                    ]),
                  ).animate().fadeIn(delay: 200.ms).moveY(begin: 30, end: 0),
                  const SizedBox(height: 32),
                  Text('© 2026 AppLocker Security. Secure Management.', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildLogo() {
    return Column(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]), child: const Icon(Icons.shield_rounded, color: Colors.white, size: 28)),
      const SizedBox(height: 12),
      RichText(textAlign: TextAlign.center, text: TextSpan(style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5), children: [const TextSpan(text: 'App', style: TextStyle(color: Color(0xFF1E293B))), const TextSpan(text: 'Locker', style: TextStyle(color: Color(0xFF6366F1)))])),
      Text('PARENTAL CONTROL', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 4)),
    ]);
  }

  Widget _buildSignInButton() {
    return Container(
      width: double.infinity, height: 50, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], begin: Alignment.centerLeft, end: Alignment.centerRight), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Material(color: Colors.transparent, child: InkWell(onTap: _isLoading ? null : _login, borderRadius: BorderRadius.circular(12), child: Center(child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text('Sign In to Admin', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))))),
    );
  }

  Widget _buildSocialButtons() {
    return Row(children: [
      Expanded(child: _SocialButton(label: 'Google', icon: Icons.g_mobiledata_rounded, color: const Color(0xFFEA4335), isOutline: true, onTap: () => _socialLogin('google'))),
      const SizedBox(width: 12),
      Expanded(child: _SocialButton(label: 'Facebook', icon: Icons.facebook_rounded, color: const Color(0xFF1877F2), isOutline: false, onTap: () => _socialLogin('facebook'))),
    ]);
  }
}

class _SocialButton extends StatelessWidget {
  final String label; final IconData icon; final Color color; final bool isOutline; final VoidCallback onTap;
  const _SocialButton({required this.label, required this.icon, required this.color, required this.isOutline, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isOutline ? Colors.white : color,
        borderRadius: BorderRadius.circular(12),
        border: isOutline ? Border.all(color: const Color(0xFFE2E8F0)) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: isOutline ? color : Colors.white, size: label == 'Google' ? 28 : 20),
            if (label != 'Google') const SizedBox(width: 8),
            Text(label, style: GoogleFonts.outfit(color: isOutline ? const Color(0xFF475569) : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  final String error; const _StartupErrorApp({required this.error});
  @override Widget build(BuildContext context) { return MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Startup failed:\n$error', textAlign: TextAlign.center))))); }
}
