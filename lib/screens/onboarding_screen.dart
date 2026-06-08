import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/mascot_widget.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _locationEnabled = false;
  bool _cameraEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // Welcome card with mascot
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: kYellowLight,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kYellow, width: 1.5),
                      ),
                      child: Column(
                        children: [
                          const MascotWidget(size: 120),
                          const SizedBox(height: 12),
                          Text(
                            'Welcome to SeoulFit',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: kInk,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Your AI travel buddy for Seoul adventures',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: kSubtext,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Sign in buttons
                    _PillButton(
                      label: 'Continue with Apple',
                      icon: Icons.apple,
                      backgroundColor: kInk,
                      foregroundColor: Colors.white,
                      onTap: () {},
                    ),
                    const SizedBox(height: 10),
                    _PillButton(
                      label: 'Continue with Google',
                      icon: null,
                      googleIcon: true,
                      backgroundColor: kCard,
                      foregroundColor: kInk,
                      border: true,
                      onTap: () {},
                    ),
                    const SizedBox(height: 28),
                    // Permissions section
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'App Permissions',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kSubtext,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PermissionTile(
                      icon: Icons.location_on_rounded,
                      title: 'Location Access',
                      subtitle: 'For real-time nearby recommendations',
                      value: _locationEnabled,
                      onChanged: (v) async {
                        if (v) {
                          final status =
                              await Permission.location.request();
                          setState(() =>
                              _locationEnabled = status.isGranted);
                        } else {
                          setState(() => _locationEnabled = false);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _PermissionTile(
                      icon: Icons.camera_alt_rounded,
                      title: 'Camera',
                      subtitle: 'For Seoul Lens AR feature',
                      value: _cameraEnabled,
                      onChanged: (v) async {
                        if (v) {
                          final status =
                              await Permission.camera.request();
                          setState(() =>
                              _cameraEnabled = status.isGranted);
                        } else {
                          setState(() => _cameraEnabled = false);
                        }
                      },
                    ),
                    const SizedBox(height: 28),
                    // CTA
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/chat'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kMint,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50)),
                          elevation: 0,
                        ),
                        child: Text(
                          'Get Started',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'By continuing you agree to our Terms & Privacy Policy',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: kSubtext),
                    ),
                    const SizedBox(height: 24),
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

class _PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool googleIcon;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool border;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    this.icon,
    this.googleIcon = false,
    required this.backgroundColor,
    required this.foregroundColor,
    this.border = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(50),
          border: border
              ? Border.all(color: kCardBorder, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (googleIcon)
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(right: 10),
                child: CustomPaint(painter: _GoogleGPainter()),
              )
            else if (icon != null) ...[
              Icon(icon, color: foregroundColor, size: 20),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
      const Color(0xFFEA4335),
    ];
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.8;
    paint.color = colors[0];
    canvas.drawArc(Rect.fromLTWH(0, 0, size.width, size.height), -0.3, 2.0, false, paint);
    paint.color = colors[1];
    canvas.drawArc(Rect.fromLTWH(0, 0, size.width, size.height), 1.7, 1.1, false, paint);
    paint.color = colors[2];
    canvas.drawArc(Rect.fromLTWH(0, 0, size.width, size.height), 2.8, 0.85, false, paint);
    paint.color = colors[3];
    canvas.drawArc(Rect.fromLTWH(0, 0, size.width, size.height), 3.65, 0.9, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kMintLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: kMint, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                Text(subtitle,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: kSubtext)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: kMint,
          ),
        ],
      ),
    );
  }
}