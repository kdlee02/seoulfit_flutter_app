import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/itinerary_map.dart';
import '../models/travel_state.dart';
import '../providers/travel_provider.dart';

/// A connection between two consecutive selected stops. Walk/car estimates plus
/// a Kakao Map deep-link between the two stops.
class _Hop {
  final double? distanceKm;
  final int? walkMin;
  final int? carMin;
  final String? kakaoUrl;
  const _Hop({this.distanceKm, this.walkMin, this.carMin, this.kakaoUrl});

  int get etaMin => walkMin ?? 0;
}

class RouteVariationScreen extends StatefulWidget {
  const RouteVariationScreen({super.key});

  @override
  State<RouteVariationScreen> createState() => _RouteVariationScreenState();
}

class _RouteVariationScreenState extends State<RouteVariationScreen> {
  @override
  void initState() {
    super.initState();
    // Build the ODsay transit options for the selected stops as soon as the
    // route is shown (the Transit screen used to trigger this on a button tap).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<TravelProvider>();
      if (p.selectedStops.length >= 2 &&
          p.recomputedLegs == null &&
          !p.legsLoading) {
        p.recomputeTransit();
      }
    });
  }

  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Kakao Map walking-route deep-link, built client-side from coordinates
  /// (same scheme the backend uses) so the route screen needs no API call.
  static String? _kakaoUrl(Poi a, Poi b) {
    if (a.lat == null || a.lng == null || b.lat == null || b.lng == null) {
      return null;
    }
    return 'https://m.map.kakao.com/scheme/route'
        '?sp=${a.lat},${a.lng}&ep=${b.lat},${b.lng}&by=foot';
  }

  _Hop _hop(TravelProvider p, Poi a, Poi b) {
    final leg = p.legBetween(a, b);
    var dist = leg?.distanceKm;
    var walk = leg?.walkMinutes;
    var car = leg?.carMinutes;
    if (dist == null &&
        a.lat != null &&
        a.lng != null &&
        b.lat != null &&
        b.lng != null) {
      dist = _haversineKm(a.lat!, a.lng!, b.lat!, b.lng!);
      walk = (dist / 4 * 60).round();
      car = (dist / 30 * 60).round();
    }
    return _Hop(
      distanceKm: dist,
      walkMin: walk,
      carMin: car,
      kakaoUrl: _kakaoUrl(a, b),
    );
  }

  static String _clock(int minutesFrom9am) {
    final total = 9 * 60 + minutesFrom9am;
    var h = (total ~/ 60) % 24;
    final m = total % 60;
    final ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')} $ampm';
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openMaps(double lat, double lng) async {
    await _open('https://maps.google.com/?q=$lat,$lng');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TravelProvider>();
    final stops = provider.selectedStops.isNotEmpty
        ? provider.selectedStops
        : provider.allPois;

    if (stops.length < 2) {
      return Scaffold(
        backgroundColor: kCanvas,
        body: SafeArea(
          child: Column(
            children: [
              const AppStatusBar(),
              const Spacer(),
              const Icon(Icons.route_rounded, size: 48, color: kSubtext),
              const SizedBox(height: 12),
              Text('No route yet',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 6),
              Text('Select at least two stops to build a route.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: kSubtext)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/user-selection'),
                child: const Text('Select Stops'),
              ),
              const Spacer(),
              const AppBottomNav(currentIndex: 1),
            ],
          ),
        ),
      );
    }

    final hops = <_Hop>[
      for (var i = 0; i < stops.length - 1; i++)
        _hop(provider, stops[i], stops[i + 1]),
    ];

    // Cumulative arrival times.
    final arrivals = <int>[];
    var t = 0;
    for (var i = 0; i < stops.length; i++) {
      arrivals.add(t);
      final stay = stops[i].stayMinutes > 0 ? stops[i].stayMinutes : 60;
      t += stay + (i < hops.length ? hops[i].etaMin : 0);
    }
    final walkTotal = hops.fold<int>(0, (s, h) => s + (h.walkMin ?? 0));
    final dayCount = provider.itinerary?.days.length ?? 1;

    // ODsay transit leg for hop i: prefer the recomputed legs for the current
    // selection, otherwise the legs from the original itinerary.
    final recomputed = provider.recomputedLegs;
    final hasRecomputed =
        recomputed != null && recomputed.length == stops.length - 1;
    TransitLeg? transitFor(int i) => hasRecomputed
        ? recomputed[i]
        : provider.legBetween(stops[i], stops[i + 1]);

    // Synthetic single-day itinerary so we can reuse the OSM map widget.
    final routeItinerary = Itinerary(
      summary: '',
      sources: const [],
      days: [
        ItineraryDay(
          day: 1,
          theme: 'Your selected route',
          pois: stops,
          estimatedCost: '',
        ),
      ],
    );

    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: kMintLight,
                          borderRadius: BorderRadius.circular(50)),
                      child: Text('${stops.length} stops selected',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: kMint)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Your Route',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kInk)),
                  Text('Walking, transit & Kakao Map links between stops',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: kSubtext)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ItineraryMap(
                          itinerary: routeItinerary, height: 220),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Full Route Summary',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: kInk)),
                          const SizedBox(height: 10),
                          for (var i = 0; i < stops.length; i++) ...[
                            _SummaryCard(
                              index: i + 1,
                              poi: stops[i],
                              time: _clock(arrivals[i]),
                              onMaps: stops[i].lat != null &&
                                      stops[i].lng != null
                                  ? () =>
                                      _openMaps(stops[i].lat!, stops[i].lng!)
                                  : null,
                            ),
                            if (i < hops.length) ...[
                              _HopRow(
                                hop: hops[i],
                                onKakao: hops[i].kakaoUrl != null
                                    ? () => _open(hops[i].kakaoUrl!)
                                    : null,
                              ),
                              _InlineTransitCard(
                                leg: transitFor(i),
                                loading: provider.legsLoading,
                              ),
                            ],
                          ],
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kMintLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _StatItem('Days', '$dayCount'),
                                _StatItem('Stops', '${stops.length}'),
                                _StatItem('Walk', '~$walkTotal min'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const AppBottomNav(currentIndex: 1),
          ],
        ),
      ),
    );
  }
}

/// Inline transit options for one hop, woven into the route-summary timeline.
/// Shares the light card / mint visual language of the rest of the summary and
/// hangs off the same connector line. No Kakao Map button — that link lives on
/// the hop row directly above it.
class _InlineTransitCard extends StatelessWidget {
  final TransitLeg? leg;
  final bool loading;
  const _InlineTransitCard({required this.leg, required this.loading});

  static String _wonFmt(int won) {
    final s = won.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// Wraps [child] so it hangs off the timeline's connector line, matching the
  /// indent of the hop row above it.
  Widget _connector(Widget child) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 2, color: kCardBorder),
            const SizedBox(width: 16),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = leg?.transitOptions ?? const <TransitOption>[];

    if (options.isEmpty) {
      if (loading) {
        return _connector(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: kMint),
              ),
              const SizedBox(width: 8),
              Text('Finding subway & bus routes…',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: kSubtext,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final headlineMinutes = options.first.totalMinutes;

    return _connector(
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kMintLight.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kMint.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.directions_transit_rounded,
                  color: kMint, size: 15),
              const SizedBox(width: 6),
              Text('Public transit',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kInk)),
              const SizedBox(width: 6),
              Text('· ${options.length} option${options.length == 1 ? "" : "s"}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: kSubtext,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              if (headlineMinutes != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kMint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('fastest ~$headlineMinutes min',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
            ]),
            const SizedBox(height: 10),
            for (var i = 0; i < options.length; i++)
              _OptionBlock(
                opt: options[i],
                wonFmt: _wonFmt,
                isLast: i == options.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

/// One ODsay route option (subway / bus / subway+bus), light-themed to match
/// the route summary.
class _OptionBlock extends StatelessWidget {
  final TransitOption opt;
  final String Function(int) wonFmt;
  final bool isLast;
  const _OptionBlock(
      {required this.opt, required this.wonFmt, this.isLast = false});

  IconData get _icon {
    switch (opt.type) {
      case 1:
        return Icons.subway_rounded;
      case 2:
        return Icons.directions_bus_rounded;
      default:
        return Icons.alt_route_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (opt.totalMinutes != null) '${opt.totalMinutes} min',
      if (opt.fareWon != null) '₩${wonFmt(opt.fareWon!)}',
      if ((opt.transfers ?? 0) > 0) '${opt.transfers} transfer',
      if (opt.walkMeters != null) 'walk ${opt.walkMeters}m',
    ].join(' · ');

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_icon, size: 14, color: kMint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(opt.typeLabel,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: kInk)),
            ),
            if (meta.isNotEmpty)
              Text(meta,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kMint)),
          ]),
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

/// One ODsay segment line rendered as a light timeline row.
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
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4),
            decoration:
                const BoxDecoration(color: kMint, shape: BoxShape.circle),
          ),
          if (!isLast)
            Container(
                width: 2,
                height: 18,
                color: kMint.withValues(alpha: 0.25),
                margin: const EdgeInsets.symmetric(vertical: 2)),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 0, bottom: isLast ? 0 : 7),
            child: Text(text,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: kSubtext,
                    height: 1.35)),
          ),
        ),
      ],
    );
  }
}

/// Inline hop between summary cards: walk/car estimate + a Kakao Map link.
class _HopRow extends StatelessWidget {
  final _Hop hop;
  final VoidCallback? onKakao;
  const _HopRow({required this.hop, required this.onKakao});

  @override
  Widget build(BuildContext context) {
    final label = [
      if (hop.distanceKm != null) '${hop.distanceKm!.toStringAsFixed(1)} km',
      if (hop.walkMin != null) '🚶 ${hop.walkMin} min',
      if (hop.carMin != null) '🚗 ${hop.carMin} min',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 8),
      child: Row(
        children: [
          Container(width: 2, height: 24, color: kCardBorder),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: kSubtext)),
          ),
          if (onKakao != null)
            GestureDetector(
              onTap: onKakao,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE000),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.map_outlined, size: 13, color: Colors.black),
                  const SizedBox(width: 4),
                  Text('Kakao Map',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int index;
  final Poi poi;
  final String time;
  final VoidCallback? onMaps;
  const _SummaryCard({
    required this.index,
    required this.poi,
    required this.time,
    required this.onMaps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(color: kMint, shape: BoxShape.circle),
          child: Center(
            child: Text('$index',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(poi.name,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
            Text(
                [
                  if (poi.type.isNotEmpty) poi.type,
                  time,
                ].join(' · '),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: kSubtext)),
          ]),
        ),
        if (onMaps != null)
          GestureDetector(
            onTap: onMaps,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Maps',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.w800, color: kMint)),
        Text(label,
            style:
                GoogleFonts.plusJakartaSans(fontSize: 11, color: kSubtext)),
      ],
    );
  }
}
