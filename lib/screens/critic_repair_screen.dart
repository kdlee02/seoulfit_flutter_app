import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';

class CriticRepairScreen extends StatelessWidget {
  const CriticRepairScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const total = 12;
    const fixed = 3;
    const checks = [
      _CheckItem(label: 'Schedule Conflicts', passed: true),
      _CheckItem(label: 'Route Efficiency', passed: true),
      _CheckItem(label: 'Opening Hours', passed: false),
    ];
    const logs = [
      'Moved Gyeongbokgung Palace visit from 18:00 to 09:00 (closes at 17:00)',
      'Reordered stops to reduce total travel distance by 2.3 km',
      'Added 30-min buffer between Bukchon Hanok Village and lunch stop',
    ];

    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: kMintLight,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded,
                                size: 13, color: kMint),
                            const SizedBox(width: 5),
                            Text(
                              'AI Verification Report',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: kMint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '✨ AI Optimized\nYour Itinerary!',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: kInk,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We checked $total constraints and fixed $fixed issues.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: kSubtext),
                    ),
                    const SizedBox(height: 24),

                    // AI Verification Summary Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kCardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Verification Summary',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kInk,
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final check in checks) ...[
                            Row(
                              children: [
                                Text(
                                  check.passed ? '✅' : '❌',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  check.label,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13, color: kInk),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Auto-Correction Logs
                    Text(
                      'Auto-Correction Logs',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kInk,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (var i = 0; i < logs.length; i++) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kCardBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: kMintLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: kMint,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                logs[i],
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: kSubtext,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < logs.length - 1) const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/itinerary-map'),
                        icon: const Icon(Icons.map_rounded, size: 18),
                        label: const Text('View My Final Route'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kMint,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50)),
                          elevation: 0,
                          textStyle: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            const AppBottomNav(currentIndex: 0),
          ],
        ),
      ),
    );
  }
}

class _CheckItem {
  final String label;
  final bool passed;
  const _CheckItem({required this.label, required this.passed});
}
