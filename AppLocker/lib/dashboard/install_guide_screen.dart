// lib/dashboard/install_guide_screen.dart
// APK Installation Guide Screen - Simplified step text

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

class InstallGuideScreen extends StatefulWidget {
  const InstallGuideScreen({super.key});

  @override
  State<InstallGuideScreen> createState() => _InstallGuideScreenState();
}

class _InstallGuideScreenState extends State<InstallGuideScreen> {
  final ScrollController _scrollController = ScrollController();
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 768;
    final isDesktop = size.width >= 1024;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Day theme background
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF), // White app bar
        elevation: 1,
        title: Text(
          'APK Installation Guide',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E293B), // Dark text
            fontSize: isMobile ? 18 : 24,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF6366F1)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _openWebGuide,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(
              'Web Version',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6366F1),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        // Remove maxWidth constraint for full screen on PC
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : isDesktop ? 24 : 20, // Reduced margins for PC
          vertical: 16,
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isMobile ? 24 : 32),
                margin: EdgeInsets.only(bottom: isMobile ? 24 : 32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'APK Installation Guide',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontSize: isMobile ? 24 : 32,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Follow these steps to install AppLocker on your Android device',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                        fontSize: isMobile ? 14 : 16,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -20),

              // Steps Grid - 2 columns for desktop, 1 for mobile
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = isDesktop ? 2 : 1;
                  final childAspectRatio = isDesktop ? 1.4 : isMobile ? 1.2 : 1.4;
                  final mainAxisSpacing = isMobile ? 20.0 : 30.0;
                  final crossAxisSpacing = isDesktop ? 30.0 : 0.0;
                  
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: childAspectRatio,
                      mainAxisSpacing: mainAxisSpacing,
                      crossAxisSpacing: crossAxisSpacing,
                    ),
                    itemCount: 41, // 0.png + 1.png through 40.png
                    itemBuilder: (context, index) {
                      return _buildStepCard(index, isMobile, isDesktop);
                    },
                  );
                },
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard(int stepIndex, bool isMobile, bool isDesktop) {
    // Step 0 uses 0.png, Step 1 uses 1.png, etc.
    final imageNumber = stepIndex;
    final displayStep = stepIndex + 1;
    
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF), // White cards for day theme
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0), // Light border
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withOpacity(0.05), // Light shadow
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step header - simplified text only
          Row(
            children: [
              Container(
                width: isMobile ? 32 : 48, // Smaller for mobile
                height: isMobile ? 32 : 48, // Smaller for mobile
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
                ),
                child: Center(
                  child: Text(
                    '$displayStep',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: isMobile ? 14 : 20, // Smaller font for mobile
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Step $displayStep', // Simplified text - no subtext
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B), // Dark text
                    fontSize: isMobile ? 16 : 20, // Smaller for mobile
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: isMobile ? 12 : 20),
          
          // Step image - full image without cropping
          Expanded(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFFF8FAFC), // Light background for image
              child: Image.asset(
                'assets/guide/$imageNumber.png',
                fit: BoxFit.contain, // Use contain to show full image
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: const Color(0xFFF8FAFC),
                    width: double.infinity,
                    height: double.infinity,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_not_supported_rounded,
                            size: isMobile ? 24 : 32,
                            color: const Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Image $imageNumber',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF94A3B8),
                              fontSize: isMobile ? 10 : 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (displayStep * 30).ms).slideY(begin: 20);
  }

  void _openWebGuide() async {
    final url = Uri.parse('https://applocker-c39cf.web.app/apk_install_guide');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch web guide'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }
}
