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
/// a Kakao Map deep-link — no ODsay here (that lives on the Transit screen).
class _Hop {
  final double? distanceKm;
  final int? walkMin;
  final int? carMin;
  final String? kakaoUrl;
  const _Hop({this.distanceKm, this.walkMin, this.carMin, this.kakaoUrl});

  int get etaMin => walkMin ?? 0;
}

class RouteVariationScreen extends StatelessWidget {
  const RouteVariationScreen({super.key});

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

  Future<void> _openDirections(List<Poi> stops) async {
    final pts = stops.where((p) => p.lat != null && p.lng != null).toList();
    if (pts.isEmpty) return;
    final origin = '${pts.first.lat},${pts.first.lng}';
    final dest = '${pts.last.lat},${pts.last.lng}';
    final mid = pts.length > 2
        ? pts
            .sublist(1, pts.length - 1)
            .map((p) => '${p.lat},${p.lng}')
            .join('|')
        : '';
    await _open(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=$origin&destination=$dest'
      '${mid.isNotEmpty ? '&waypoints=$mid' : ''}'
      '&travelmode=transit',
    );
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
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _openDirections(stops),
                      icon: const Icon(Icons.map_rounded,
                          size: 16, color: kMint),
                      label: Text('Directions',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: kMint)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Your Route',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kInk)),
                  Text('Walking times & Kakao Map links between stops',
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
                            if (i < hops.length)
                              _HopRow(
                                hop: hops[i],
                                onKakao: hops[i].kakaoUrl != null
                                    ? () => _open(hops[i].kakaoUrl!)
                                    : null,
                              ),
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
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _openDirections(stops),
                              icon: const Icon(Icons.navigation_rounded,
                                  size: 18),
                              label: const Text(
                                  'Get Directions in Google Maps'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A73E8),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50)),
                                elevation: 0,
                                textStyle: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              // Kick off the ODsay recompute, THEN open the
                              // Transit screen where it's displayed.
                              onPressed: () {
                                context
                                    .read<TravelProvider>()
                                    .recomputeTransit();
                                Navigator.pushNamed(context, '/transit-explore');
                              },
                              icon: const Icon(
                                  Icons.directions_transit_rounded,
                                  size: 18),
                              label: const Text('Transit Guide & Explore'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kMint,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
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
