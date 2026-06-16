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
import '../services/api_service.dart';

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
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<TravelProvider>();
      if (p.selectedStops.length >= 2 &&
          p.recomputedLegs == null &&
          !p.legsLoading) {
        p.recomputeTransit();
      }
    });
  }

  Widget _dayPills(List<int> days) {
    if (days.length <= 1) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final day in days)
            GestureDetector(
              onTap: () => setState(() => _selectedDay = day),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: day == _selectedDay ? kMint : Colors.transparent,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: day == _selectedDay ? kMint : kCardBorder,
                  ),
                ),
                child: Text(
                  'Day $day',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: day == _selectedDay ? Colors.white : kSubtext,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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

    // All unique day numbers across the selected stops.
    final dayNumbers = <int>{for (final s in stops) s.day == 0 ? 1 : s.day}
        .toList()
      ..sort();

    // Pick active day (default to first).
    final activeDay = dayNumbers.contains(_selectedDay)
        ? _selectedDay!
        : dayNumbers.first;
    if (_selectedDay != activeDay) _selectedDay = activeDay;

    // Stops for the active day only.
    final dayStops = [
      for (final s in stops)
        if ((s.day == 0 ? 1 : s.day) == activeDay) s,
    ];

    final hops = <_Hop>[
      for (var i = 0; i < dayStops.length - 1; i++)
        _hop(provider, dayStops[i], dayStops[i + 1]),
    ];

    // Cumulative arrival times.
    final arrivals = <int>[];
    var t = 0;
    for (var i = 0; i < dayStops.length; i++) {
      arrivals.add(t);
      final stay = dayStops[i].stayMinutes > 0 ? dayStops[i].stayMinutes : 60;
      t += stay + (i < hops.length ? hops[i].etaMin : 0);
    }
    final walkTotal = hops.fold<int>(0, (s, h) => s + (h.walkMin ?? 0));
    final dayCount = provider.itinerary?.days.length ?? 1;

    // Transit legs: always use name-based lookup so day-filtered indices work.
    TransitLeg? transitFor(int i) =>
        provider.legBetween(dayStops[i], dayStops[i + 1]);

    // Synthetic itinerary for the map widget (selected day only).
    final routeItinerary = Itinerary(
      summary: '',
      sources: const [],
      days: [
        ItineraryDay(
          day: activeDay,
          theme: 'Day $activeDay',
          pois: dayStops,
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
                          _dayPills(dayNumbers),
                          if (dayNumbers.length > 1) const SizedBox(height: 12),
                          if (!provider.transitTipDismissed) ...[
                            _TransitTipBanner(
                              onDismiss: () =>
                                  provider.dismissTransitTip(),
                            ),
                            const SizedBox(height: 12),
                          ],
                          for (var i = 0; i < dayStops.length; i++) ...[
                            _SummaryCard(
                              index: i + 1,
                              poi: dayStops[i],
                              time: _clock(arrivals[i]),
                              onMaps: dayStops[i].lat != null &&
                                      dayStops[i].lng != null
                                  ? () => _openMaps(
                                      dayStops[i].lat!, dayStops[i].lng!)
                                  : null,
                            ),
                            if (i < hops.length) ...[
                              _WalkAdviceBanner(
                                km: hops[i].distanceKm,
                                walkMin: hops[i].walkMin,
                              ),
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
                                _StatItem('Stops', '${dayStops.length}'),
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

/// Short English label for an ODsay path type (1=subway, 2=bus, 3=both).
String _modeLabel(int? type) {
  switch (type) {
    case 1:
      return 'Subway';
    case 2:
      return 'Bus';
    case 3:
      return 'Bus + Subway';
    default:
      return 'Route';
  }
}

IconData _modeIcon(int? type) {
  switch (type) {
    case 1:
      return Icons.subway_rounded;
    case 2:
      return Icons.directions_bus_rounded;
    case 3:
      return Icons.alt_route_rounded;
    default:
      return Icons.directions_transit_rounded;
  }
}

/// Lines where an express (급행) service runs alongside the local (완행) train,
/// so a tourist can board the wrong one. Matched against ODsay segment text in
/// both Korean and the romanised names ODsay sometimes returns.
const _expressLineTokens = [
  '9호선',
  '수인분당',
  '수인·분당',
  '분당선',
  '경의중앙',
  'line 9',
  'suin',
  'bundang',
  'gyeongui',
];

bool _segmentHasExpressLine(List<String> segments) {
  for (final seg in segments) {
    final s = seg.toLowerCase();
    if (_expressLineTokens.any(s.contains)) return true;
  }
  return false;
}

/// Station you get off at: the destination (after "→") of the last non-walking
/// segment. Null if it can't be parsed.
String? _alightStation(List<String> segments) {
  for (final seg in segments.reversed) {
    final s = seg.toLowerCase();
    if (seg.contains('도보') || s.contains('walk')) continue;
    final arrow = seg.indexOf('→');
    if (arrow < 0) continue;
    var dest = seg.substring(arrow + 1);
    final paren = dest.indexOf('(');
    if (paren >= 0) dest = dest.substring(0, paren);
    final out = dest.trim();
    if (out.isNotEmpty) return out;
  }
  return null;
}

/// Exit number, if any segment carries one ("2번 출구" / "Exit 2").
String? _exitNumber(List<String> segments) {
  final ko = RegExp(r'(\d+)\s*번\s*출구');
  final en = RegExp(r'[Ee]xit\s*(\d+)');
  for (final seg in segments) {
    final m = ko.firstMatch(seg) ?? en.firstMatch(seg);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Named (non-numbered) subway lines, mapped to a label a foreign rider can
/// match against the platform signage.
/// Matched case-insensitively against the cleaned line name, in both the Korean
/// (lang=0) and English (lang=1) forms ODsay returns. Order matters: more
/// specific keys come first because matching is substring-based — e.g. "bundang"
/// is a substring of "sinbundang"/"suin-bundang", so the bare forms come last.
const _namedLines = {
  '수인분당': 'the Suin-Bundang Line',
  '수인·분당': 'the Suin-Bundang Line',
  '수인.분당': 'the Suin-Bundang Line',
  'suin-bundang': 'the Suin-Bundang Line',
  '신분당': 'the Sinbundang Line',
  'sinbundang': 'the Sinbundang Line',
  'shinbundang': 'the Sinbundang Line',
  '경의중앙': 'the Gyeongui-Jungang Line',
  'gyeongui-jungang': 'the Gyeongui-Jungang Line',
  'gyeongui': 'the Gyeongui-Jungang Line',
  '공항철도': 'the Airport Railroad (AREX)',
  'airport railroad': 'the Airport Railroad (AREX)',
  '경춘': 'the Gyeongchun Line',
  'gyeongchun': 'the Gyeongchun Line',
  '우이신설': 'the Ui-Sinseol Line',
  'ui-sinseol': 'the Ui-Sinseol Line',
  '분당': 'the Bundang Line',
  'bundang': 'the Bundang Line',
};

/// One parsed transit segment (start/end station + a rider-friendly line label).
class _Seg {
  final String line;
  final String start;
  final String end;
  const _Seg(this.line, this.start, this.end);
}

/// English-ish line label from an ODsay lane chunk
/// (e.g. "🚇 지하철 수도권 2호선" → "Line 2", "🚌 버스 472" → "Bus 472").
String _lineLabel(String chunk) {
  final isBus = chunk.contains('🚌') ||
      chunk.contains('버스') ||
      RegExp(r'\bbus\b', caseSensitive: false).hasMatch(chunk);
  var c = chunk
      .replaceAll('🚇', '')
      .replaceAll('🚌', '')
      .replaceAll('🚶', '')
      .replaceFirst('지하철', '')
      .replaceFirst('버스', '')
      .replaceAll('수도권', '')
      // English structural labels ODsay emits in lang=1 ("Subway"/"Bus").
      .replaceAll(RegExp(r'\b(Subway|Bus)\b', caseSensitive: false), '')
      .trim();
  if (isBus) return c.isEmpty ? 'the bus' : 'Bus $c';
  // Korean "2호선" or English "Line 2".
  final m = RegExp(r'(\d+)\s*호선').firstMatch(c) ??
      RegExp(r'Line\s*(\d+)', caseSensitive: false).firstMatch(c);
  if (m != null) return 'Line ${m.group(1)}';
  for (final e in _namedLines.entries) {
    if (c.toLowerCase().contains(e.key.toLowerCase())) return e.value;
  }
  return c;
}

/// Parse one ODsay segment string into a [_Seg], or null for walking legs.
_Seg? _parseTransitSeg(String seg) {
  if (seg.contains('도보') || seg.toLowerCase().contains('walk')) return null;
  final arrow = seg.indexOf('→');
  if (arrow < 0) return null;
  List<String> chunks(String s) =>
      s.split('  ').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final left = chunks(seg.substring(0, arrow));
  final right = chunks(seg.substring(arrow + 1));
  final lane = left.isNotEmpty ? left.first : '';
  final start = left.length > 1 ? left.last : '';
  final end = right.isNotEmpty ? right.first : '';
  return _Seg(_lineLabel(lane), start, end);
}

/// A transfer point: the station you change at + the line you change to.
class _Transfer {
  final String station;
  final String toLine;
  const _Transfer(this.station, this.toLine);
}

List<_Transfer> _transfersIn(List<String> segments) {
  final segs = <_Seg>[];
  for (final s in segments) {
    final p = _parseTransitSeg(s);
    if (p != null) segs.add(p);
  }
  final out = <_Transfer>[];
  for (var i = 0; i < segs.length - 1; i++) {
    final st = segs[i].end.isNotEmpty ? segs[i].end : segs[i + 1].start;
    out.add(_Transfer(st, segs[i + 1].line));
  }
  return out;
}

/// Normalise a station name for table lookup: drop the "역" suffix and any bus
/// stop "N번출구" decoration ODsay sometimes appends.
String _normStation(String s) {
  var t = s.trim();
  t = t.replaceAll(RegExp(r'\d+번출입?구'), '');
  t = t.replaceAll('출입구', '').replaceAll('출구', '').trim();
  if (t.endsWith('역')) t = t.substring(0, t.length - 1);
  return t.trim();
}

/// The big / complex interchanges where a first-time foreign rider should
/// budget extra time — long underground walkways, multiple lines, easy to get
/// turned around. Keyed by normalised station name (no "역"). Roughly the ~16
/// stations a tourist most often passes through; everything else is treated as
/// a quick "follow the colored signs" transfer.
const _hardTransferStations = <String>{
  '서울', '신도림', '동대문역사문화공원', '고속터미널', '왕십리', '종로3가',
  '충무로', '공덕', '디지털미디어시티', '사당', '잠실', '김포공항',
  '청량리', '교대', '강남', '약수',
};

/// Same interchanges in ODsay's English romanisation (lang=1), substring-matched
/// against the raw station name. Best effort — a miss only downgrades a transfer
/// to a simple "EASY" change, never an error.
// Tokens verified against ODsay's actual lang=1 station names. Substring-matched,
// so the shortest distinctive form is used (more robust to trailing decorations).
// 'university of education' = 교대 (Seoul National University of Education) — kept
// distinct from 서울대입구 ("Seoul Nat'l Univ.") to avoid a false positive.
const _hardTransferStationsEn = <String>[
  'seoul station', 'sindorim', 'dongdaemun history', 'express bus terminal',
  'wangsimni', 'jongno 3', 'chungmuro', 'gongdeok', 'digital media city',
  'sadang', 'jamsil', 'gimpo international airport', 'cheongnyangni',
  'university of education', 'gangnam', 'yaksu',
];

/// Whether a transfer station is one of Seoul's big/complex interchanges,
/// checking the Korean name (lang=0) and the English romanisation (lang=1).
bool _isHardTransfer(String station) {
  if (_hardTransferStations.contains(_normStation(station))) return true;
  final en = station.toLowerCase();
  return _hardTransferStationsEn.any(en.contains);
}

/// Inline transit options for one hop, woven into the route-summary timeline.
/// Shows one mode button per available ODsay option (지하철 / 버스 / 버스+지하철)
/// and reveals only the selected one's detail, so a first-time visitor isn't
/// buried under three stacked routes at once. Hangs off the same connector line
/// as the hop row above it; the Kakao Map link lives on that row.
class _InlineTransitCard extends StatefulWidget {
  final TransitLeg? leg;
  final bool loading;
  const _InlineTransitCard({required this.leg, required this.loading});

  @override
  State<_InlineTransitCard> createState() => _InlineTransitCardState();
}

class _InlineTransitCardState extends State<_InlineTransitCard> {
  int _selected = 0;

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
    final options = widget.leg?.transitOptions ?? const <TransitOption>[];

    if (options.isEmpty) {
      if (widget.loading) {
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

    // Options arrive sorted fastest-first; clamp the selection in case the leg
    // changed (e.g. a different day) under us.
    final selected = _selected.clamp(0, options.length - 1);

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
              Text('· tap a mode',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: kSubtext,
                      fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 10),
            // Mode toggle — one button per available option.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < options.length; i++)
                  _ModeButton(
                    label: _modeLabel(options[i].type),
                    icon: _modeIcon(options[i].type),
                    minutes: options[i].totalMinutes,
                    selected: i == selected,
                    fastest: i == 0,
                    onTap: () => setState(() => _selected = i),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _OptionDetail(opt: options[selected], wonFmt: _wonFmt),
          ],
        ),
      ),
    );
  }
}

/// One tappable transit-mode pill (e.g. "Subway · 18 min").
class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final int? minutes;
  final bool selected;
  final bool fastest;
  final VoidCallback onTap;
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.minutes,
    required this.selected,
    required this.fastest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kMint : kCard,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
              color: selected ? kMint : kCardBorder, width: selected ? 0 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: selected ? Colors.white : kMint),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : kInk)),
          if (minutes != null) ...[
            const SizedBox(width: 6),
            Text('$minutes min',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.9)
                        : kSubtext)),
          ],
          if (fastest) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.25) : kMintLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('fastest',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : kMint)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Detail for the selected ODsay option: alight-station + exit call-out,
/// express-line warning, the meta line, then the segment timeline.
class _OptionDetail extends StatelessWidget {
  final TransitOption opt;
  final String Function(int) wonFmt;
  const _OptionDetail({required this.opt, required this.wonFmt});

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (opt.totalMinutes != null) '${opt.totalMinutes} min',
      if (opt.fareWon != null) '₩${wonFmt(opt.fareWon!)}',
      if ((opt.transfers ?? 0) > 0) '${opt.transfers} transfer',
      if (opt.walkMeters != null) 'walk ${opt.walkMeters}m',
    ].join(' · ');

    final alight = _alightStation(opt.segments);
    final exit = _exitNumber(opt.segments);
    final hasExpress = _segmentHasExpressLine(opt.segments);
    final transfers = _transfersIn(opt.segments);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_modeIcon(opt.type), size: 14, color: kMint),
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
          if (alight != null) ...[
            const SizedBox(height: 10),
            _AlightCallout(station: alight, exit: exit),
          ],
          if (hasExpress) ...[
            const SizedBox(height: 8),
            const _ExpressBadge(),
          ],
          for (final t in transfers) ...[
            const SizedBox(height: 8),
            _TransferRow(transfer: t),
          ],
          if (opt.segments.isNotEmpty) ...[
            const SizedBox(height: 10),
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

/// Big, hard-to-miss "where you get off" call-out — the moment foreign riders
/// most often get stuck. Exit number shown when ODsay carries one.
class _AlightCallout extends StatelessWidget {
  final String station;
  final String? exit;
  const _AlightCallout({required this.station, required this.exit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kMintLight.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kMint.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.flag_rounded, color: kMint, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Get off at',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kSubtext,
                      letterSpacing: 0.4)),
              Text(station,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: kInk)),
              if (exit != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('📍 Take Exit $exit',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: kMint)),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Express/local warning for lines that run both (9호선, 수인분당선,
/// 경의중앙선). Straight from survey Q14 — riders board the wrong train.
class _ExpressBadge extends StatelessWidget {
  const _ExpressBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: kYellowLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kWarningBorder.withValues(alpha: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.bolt_rounded, color: kWarningBorder, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('Express (급행) runs on this line',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: kInk)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: kWarningBorder,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('FAST',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                  'Express skips some stations and is faster. If the next train '
                  'is a local (완행), wait for the express (급행) instead.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: kInk.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ]),
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


/// Transfer call-out: tells a foreign rider whether the change at this station
/// is quick or a long/complex one, with a difficulty chip. Difficulty comes
/// from a small hardcoded table of Seoul's big interchanges ([_hardTransferStations]).
class _TransferRow extends StatelessWidget {
  final _Transfer transfer;
  const _TransferRow({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final hard = _isHardTransfer(transfer.station);
    final chipColor = hard ? kWarningBorder : kSuccess;
    final chipText = hard ? 'COMPLEX' : 'EASY';
    final signs = transfer.toLine.isNotEmpty
        ? ' Follow the signs for ${transfer.toLine}.'
        : '';
    final note = hard
        ? 'Big station with long walkways — allow about 5 extra minutes.$signs'
        : 'Quick change — just follow the colored signs.$signs';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: (hard ? kWarningBorder : kSuccess).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: chipColor.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(hard ? Icons.transfer_within_a_station_rounded : Icons.swap_calls_rounded,
            size: 18, color: chipColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: chipColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(chipText,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Transfer at ${transfer.station}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: kInk)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(note,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: kInk.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ]),
    );
  }
}

/// "Can I just walk this?" call-out that judges a hop before the raw numbers,
/// so a first-time visitor isn't left guessing whether 0.4 km is walkable.
/// Rule-based on straight-line distance:
///   ≤ 0.5 km → just walk · 0.5–1.5 km → walk or one bus · > 1.5 km → transit.
class _WalkAdviceBanner extends StatelessWidget {
  final double? km;
  final int? walkMin;
  const _WalkAdviceBanner({required this.km, required this.walkMin});

  @override
  Widget build(BuildContext context) {
    if (km == null) return const SizedBox.shrink();
    final dist = '${km!.toStringAsFixed(1)} km';
    final foot = walkMin != null ? ' · about $walkMin min on foot' : '';

    late final IconData icon;
    late final String title;
    late final String detail;
    if (km! <= 0.5) {
      icon = Icons.directions_walk_rounded;
      title = 'Just walk it ($dist$foot)';
      detail = "Same block — no need to take the subway.";
    } else if (km! <= 1.5) {
      icon = Icons.directions_walk_rounded;
      title = 'Walk, or hop one bus ($dist$foot)';
      detail = "An easy walk — or grab a bus if it's hot or you're tired.";
    } else {
      icon = Icons.directions_transit_rounded;
      title = 'Take the subway or bus ($dist)';
      detail = 'A bit far to walk — see the transit options below.';
    }

    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 2, bottom: 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 2, color: kCardBorder),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: kMintLight.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kMint.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Icon(icon, size: 18, color: kMint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: kInk)),
                        const SizedBox(height: 2),
                        Text(detail,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                height: 1.3,
                                color: kSubtext,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-time "how to pay for transit in Seoul" tip, shown on first entry to the
/// route screen and dismissable. Removes most of the fare-anxiety first-time
/// foreign visitors have before they ever tap a card.
class _TransitTipBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _TransitTipBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    Widget tip(String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: kInk, fontWeight: FontWeight.w700)),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      height: 1.4,
                      color: kInk.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500)),
            ),
          ]),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: kYellowLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kWarningBorder.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('💳', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Paying for transit in Seoul',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: kInk)),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 18, color: kSubtext),
              ),
            ),
          ]),
          tip('Just tap a T-money card or a contactless Visa/Mastercard — '
              'no need to buy a ticket each time.'),
          tip("Cash machines don't give change, so use a card if you can."),
          tip('A single-journey ticket adds a ₩500 deposit — refunded from the '
              'machine when you exit.'),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatefulWidget {
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
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _expanded = false;
  Future<String>? _tipFuture;

  void _toggleTip() {
    setState(() {
      _expanded = !_expanded;
      // Lazy-fetch the arrival tip on first open so we don't hit Gemini for
      // every stop on screen load.
      _tipFuture ??= ApiService()
          .fetchPoiArrivalTip(widget.poi.name, type: widget.poi.type);
    });
  }

  @override
  Widget build(BuildContext context) {
    final poi = widget.poi;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration:
                  const BoxDecoration(color: kMint, shape: BoxShape.circle),
              child: Center(
                child: Text('${widget.index}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(poi.name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kInk)),
                Text(
                    [
                      if (poi.type.isNotEmpty) poi.type,
                      widget.time,
                    ].join(' · '),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: kSubtext)),
              ]),
            ),
            if (widget.onMaps != null)
              GestureDetector(
                onTap: widget.onMaps,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          const SizedBox(height: 8),
          // "Am I in the right place?" toggle.
          GestureDetector(
            onTap: _toggleTip,
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              const Icon(Icons.place_rounded, size: 14, color: kMint),
              const SizedBox(width: 4),
              Text('How do I know I\'m here?',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: kMint)),
              Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 16, color: kMint),
            ]),
          ),
          if (_expanded) _arrivalTip(),
        ],
      ),
    );
  }

  Widget _arrivalTip() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: kMintLight.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kMint.withValues(alpha: 0.25)),
        ),
        child: FutureBuilder<String>(
          future: _tipFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Row(children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: kMint),
                ),
                const SizedBox(width: 8),
                Text('Looking for landmarks…',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: kSubtext,
                        fontWeight: FontWeight.w600)),
              ]);
            }
            final tip = snap.data ?? '';
            if (snap.hasError || tip.isEmpty) {
              return Text(
                  'Tip unavailable right now — check the building name and '
                  'address against your map.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5, height: 1.4, color: kSubtext));
            }
            return Text('📍 $tip',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    height: 1.45,
                    color: kInk.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500));
          },
        ),
      ),
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
