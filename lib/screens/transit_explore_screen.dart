import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';

class TransitExploreScreen extends StatelessWidget {
  const TransitExploreScreen({super.key});

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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text('Explore',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: kInk)),
                    const SizedBox(height: 2),
                    Text('Events & experiences near you',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: kSubtext)),
                    const SizedBox(height: 20),
                    // Events Near You
                    Row(children: [
                      const Icon(Icons.celebration_rounded,
                          size: 16, color: kMint),
                      const SizedBox(width: 6),
                      Text('Events Near You',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: kInk)),
                    ]),
                    const SizedBox(height: 10),
                    const SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _EventCard(
                            'K-POP Popup\nToday',
                            'SM Town Coex',
                            '2km away',
                            kYellow,
                          ),
                          SizedBox(width: 10),
                          _EventCard(
                            'Seoul DDP\nExhibition',
                            'Design Plaza',
                            'Now open',
                            kMintLight,
                          ),
                          SizedBox(width: 10),
                          _EventCard(
                            'Seongsu\nArtisan Fair',
                            'Seongsu-dong',
                            'Sat & Sun',
                            kYellowLight,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/seoul-lens'),
                        icon: const Icon(Icons.camera_alt_rounded, size: 18),
                        label: const Text('Try Seoul Lens AR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kMint,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50)),
                          elevation: 0,
                          textStyle: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            const AppBottomNav(currentIndex: 3),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final String title;
  final String venue;
  final String meta;
  final Color bgColor;
  const _EventCard(this.title, this.venue, this.meta, this.bgColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_rounded, size: 20, color: kInk),
          const SizedBox(height: 6),
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w700, color: kInk),
              maxLines: 2),
          const SizedBox(height: 4),
          Text(venue,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: kSubtext),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(meta,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: kInk)),
          ),
        ],
      ),
    );
  }
}
