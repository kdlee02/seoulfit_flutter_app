import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../models/travel_state.dart';
import '../providers/travel_provider.dart';

class TransitExploreScreen extends StatefulWidget {
  const TransitExploreScreen({super.key});

  @override
  State<TransitExploreScreen> createState() => _TransitExploreScreenState();
}

class _TransitExploreScreenState extends State<TransitExploreScreen> {
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    // Fetch fresh ODsay transit for the selected stops, unless already
    // loaded / in flight (the route screen may have kicked it off already).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<TravelProvider>();
      if (p.selectedStops.length >= 2 &&
          p.recomputedLegs == null &&
          !p.legsLoading) {
        p.recomputeTransit();
      }
    });
  }

  static const _tabs = ['Cafes', 'Food', 'Photo', 'Shop'];

  static const _cafes = [
    _SpotCard('Blue Bottle Coffee', 'Seongsu-dong', '★ 4.8', '8 min'),
    _SpotCard('Cafe Onion', 'Seongsu-dong', '★ 4.7', '5 min'),
    _SpotCard('Anthracite Coffee', 'Seongsu-dong', '★ 4.6', '12 min'),
    _SpotCard('Fritz Coffee', 'Dorim-ro', '★ 4.7', '15 min'),
  ];

  static const _food = [
    _SpotCard('Gwangjang Market', 'Jongno', '★ 4.8', '22 min'),
    _SpotCard('Seongsu Burger', 'Seongsu-dong', '★ 4.5', '6 min'),
    _SpotCard('Seoul Forest BBQ', 'Seongsu-dong', '★ 4.6', '10 min'),
    _SpotCard('Wangsimni Pork Belly', 'Wangsimni', '★ 4.4', '18 min'),
  ];

  List<_SpotCard> get _currentSpots => _selectedTab == 0 ? _cafes : _food;

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
                    Text('Transit & Explore',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: kInk)),
                    const SizedBox(height: 2),
                    Text('Real-time guide for your journey',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: kSubtext)),
                    const SizedBox(height: 16),
                    // Real ODsay transit routes from the planned itinerary.
                    const _TransitRoutesSection(),
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
                    const SizedBox(height: 20),
                    // Explore section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Explore Nearby',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: kInk)),
                        Text('Within 1km',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, color: kSubtext)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Category tabs
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_tabs.length, (i) {
                          final sel = i == _selectedTab;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedTab = i),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: sel ? kMint : kCard,
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(
                                    color: sel ? kMint : kCardBorder),
                              ),
                              child: Text(_tabs[i],
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: sel ? Colors.white : kSubtext)),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Place grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.5,
                      ),
                      itemCount: _currentSpots.length,
                      itemBuilder: (_, i) =>
                          _NearbySpotCard(spot: _currentSpots[i]),
                    ),
                    const SizedBox(height: 16),
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

/// Real transit routes for the current itinerary: one dark card per leg
/// (stop → stop) populated from the backend's ODsay options.
class _TransitRoutesSection extends StatelessWidget {
  const _TransitRoutesSection();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TravelProvider>();
    final itinerary = p.itinerary;

    if (itinerary == null) {
      return _card(
        context,
        icon: Icons.directions_transit_rounded,
        title: 'No transit routes yet',
        body: 'Plan a trip in the chat and your subway & bus routes appear here.',
        showChat: true,
      );
    }

    // While the backend recomputes ODsay for the selected stops, show a loader.
    if (p.legsLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kCardBorder),
        ),
        child: Column(children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: kMint),
          ),
          const SizedBox(height: 12),
          Text('Finding subway & bus routes…',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: kSubtext, fontWeight: FontWeight.w600)),
        ]),
      );
    }

    // Prefer the freshly recomputed legs for the selected stops; otherwise
    // fall back to the original itinerary legs.
    final entries = <({String from, String to, String label, TransitLeg leg})>[];
    final stops = p.selectedStops;
    final recomputed = p.recomputedLegs;
    if (stops.length >= 2 &&
        recomputed != null &&
        recomputed.length == stops.length - 1) {
      for (var i = 0; i < recomputed.length; i++) {
        entries.add((
          from: stops[i].name,
          to: stops[i + 1].name,
          label: 'Leg ${i + 1}',
          leg: recomputed[i],
        ));
      }
    } else {
      for (final day in itinerary.days) {
        for (var i = 0; i < day.pois.length - 1; i++) {
          if (i >= day.transitLegs.length) break;
          entries.add((
            from: day.pois[i].name,
            to: day.pois[i + 1].name,
            label: 'Day ${day.day}',
            leg: day.transitLegs[i],
          ));
        }
      }
    }

    final cards = <Widget>[];
    for (final e in entries) {
      if (!e.leg.hasAnyData && e.leg.transitOptions.isEmpty) continue;
      cards.add(_LegTransitCard(
        fromName: e.from,
        toName: e.to,
        dayLabel: e.label,
        leg: e.leg,
      ));
      cards.add(const SizedBox(height: 12));
    }

    if (cards.isEmpty) {
      return _card(
        context,
        icon: Icons.directions_transit_rounded,
        title: 'No transit legs available',
        body: 'Public-transit routes were not found for these stops.',
        showChat: false,
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: cards);
  }

  Widget _card(BuildContext context,
      {required IconData icon,
      required String title,
      required String body,
      required bool showChat}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: kSubtext),
          const SizedBox(height: 10),
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style:
                  GoogleFonts.plusJakartaSans(fontSize: 12, color: kSubtext)),
          if (showChat) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/chat'),
              icon: const Icon(Icons.chat_bubble_rounded, size: 16),
              label: const Text('Plan a Trip'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kMint,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegTransitCard extends StatelessWidget {
  final String fromName;
  final String toName;
  final String dayLabel;
  final TransitLeg leg;

  const _LegTransitCard({
    required this.fromName,
    required this.toName,
    required this.dayLabel,
    required this.leg,
  });

  static String _wonFmt(int won) {
    final s = won.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<void> _openKakao() async {
    final url = leg.kakaoCarUrl ?? leg.kakaoWalkUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final options = leg.transitOptions;
    final headlineMinutes =
        options.isNotEmpty ? options.first.totalMinutes : leg.walkMinutes;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kInk,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: day chip + fastest-time badge
          Row(children: [
            Icon(
              options.isNotEmpty
                  ? Icons.directions_transit_rounded
                  : Icons.directions_walk_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(dayLabel,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const Spacer(),
            if (headlineMinutes != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kMint.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('fastest ~$headlineMinutes min',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kMint)),
              ),
          ]),
          const SizedBox(height: 10),
          // From → To
          Text('$fromName  →  $toName',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.3)),
          if (options.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('${options.length} option${options.length == 1 ? "" : "s"}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            // Every ODsay path type: subway, bus, subway+bus.
            for (final opt in options)
              _OptionBlock(opt: opt, wonFmt: _wonFmt),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              [
                if (leg.distanceKm != null)
                  '${leg.distanceKm!.toStringAsFixed(1)} km',
                if (leg.walkMinutes != null) '🚶 ${leg.walkMinutes} min',
                if (leg.carMinutes != null) '🚗 ${leg.carMinutes} min',
              ].join('   ·   '),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
          if (leg.kakaoCarUrl != null || leg.kakaoWalkUrl != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _openKakao,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.map_outlined, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('Open in Kakao Map',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new,
                      size: 11, color: Colors.white.withValues(alpha: 0.7)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One ODsay route option (subway / bus / subway+bus) inside a leg card:
/// summary line + step-by-step segments.
class _OptionBlock extends StatelessWidget {
  final TransitOption opt;
  final String Function(int) wonFmt;
  const _OptionBlock({required this.opt, required this.wonFmt});

  @override
  Widget build(BuildContext context) {
    final summary = [
      opt.typeLabel,
      if (opt.totalMinutes != null) '${opt.totalMinutes} min',
      if (opt.fareWon != null) '₩${wonFmt(opt.fareWon!)}',
      if ((opt.transfers ?? 0) > 0) '${opt.transfers} transfer',
      if (opt.walkMeters != null) 'walk ${opt.walkMeters}m',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: kMint,
                  height: 1.35)),
          if (opt.segments.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (var i = 0; i < opt.segments.length; i++)
              _SegmentRow(
                text: opt.segments[i],
                isLast: i == opt.segments.length - 1,
              ),
          ],
        ],
      ),
    );
  }
}

/// One ODsay segment line rendered as a dark-card timeline row.
class _SegmentRow extends StatelessWidget {
  final String text;
  final bool isLast;
  const _SegmentRow({required this.text, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(color: kMint, shape: BoxShape.circle),
          ),
          if (!isLast)
            Container(
                width: 2,
                height: 20,
                color: Colors.white.withValues(alpha: 0.15),
                margin: const EdgeInsets.symmetric(vertical: 2)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 1, bottom: isLast ? 0 : 8),
            child: Text(text,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.35)),
          ),
        ),
      ],
    );
  }
}

class _SpotCard {
  final String name;
  final String area;
  final String rating;
  final String distance;
  const _SpotCard(this.name, this.area, this.rating, this.distance);
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

class _NearbySpotCard extends StatelessWidget {
  final _SpotCard spot;
  const _NearbySpotCard({required this.spot});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(spot.rating,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD97706))),
              Text(spot.distance,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: kSubtext)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(spot.name,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kInk),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              Text(spot.area,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: kSubtext)),
            ],
          ),
        ],
      ),
    );
  }
}
