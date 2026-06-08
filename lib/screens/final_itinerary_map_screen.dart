import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
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

class FinalItineraryMapScreen extends StatelessWidget {
  const FinalItineraryMapScreen({super.key});

  Future<void> _exportJson(BuildContext context, Itinerary itinerary) async {
    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(
      itinerary.raw.isNotEmpty ? itinerary.raw : {'summary': itinerary.summary},
    );
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await FileSaver.instance.saveFile(
        name: 'seoulfit_itinerary_$timestamp',
        bytes: Uint8List.fromList(utf8.encode(jsonString)),
        ext: 'json',
        mimeType: MimeType.json,
      );
      if (context.mounted) {
        _snack(context, 'Itinerary saved as JSON', kSuccess);
      }
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Save failed: $e', Colors.red);
      }
    }
  }

  void _snack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.plusJakartaSans(fontSize: 13)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  double? _score(Itinerary it) {
    final raw = it.raw;
    final direct = raw['overall_score'] ?? raw['score'];
    if (direct is num) return direct.toDouble();
    final report = raw['critic_report'];
    if (report is Map && report['overall_score'] is num) {
      return (report['overall_score'] as num).toDouble();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final itinerary = context.watch<TravelProvider>().itinerary;

    if (itinerary == null) {
      return Scaffold(
        backgroundColor: kCanvas,
        body: SafeArea(
          child: Column(
            children: [
              const AppStatusBar(),
              const Spacer(),
              const Icon(Icons.map_outlined, size: 56, color: kSubtext),
              const SizedBox(height: 12),
              Text('No itinerary yet',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 6),
              Text('Plan a trip in the chat first.',
                  style:
                      GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pushNamedAndRemoveUntil(context, '/chat', (r) => false),
                child: const Text('Go to Chat'),
              ),
              const Spacer(),
              const AppBottomNav(currentIndex: 1),
            ],
          ),
        ),
      );
    }

    final totalStops =
        itinerary.days.fold<int>(0, (n, d) => n + d.pois.length);
    final score = _score(itinerary);

    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Real OSM map with numbered, color-coded day routes.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: ItineraryMap(itinerary: itinerary, height: 260),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Final Itinerary',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: kInk),
                                ),
                              ),
                              if (score != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: kSuccess.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(50),
                                    border: Border.all(
                                        color: kSuccess.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.verified_rounded,
                                        size: 14, color: kSuccess),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Score: ${score.toStringAsFixed(score.truncateToDouble() == score ? 0 : 1)}',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: kSuccess),
                                    ),
                                  ]),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                              '$totalStops locations · ${itinerary.days.length} ${itinerary.days.length == 1 ? "day" : "days"}',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13, color: kSubtext)),
                          if (itinerary.summary.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              itinerary.summary,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: kInk,
                                  height: 1.45),
                            ),
                          ],
                          const SizedBox(height: 16),
                          // Day-by-day place list, with a transit leg row
                          // between each consecutive pair of stops.
                          for (final day in itinerary.days) ...[
                            _DayHeader(day: day),
                            for (var i = 0; i < day.pois.length; i++) ...[
                              _PoiRow(sequence: i + 1, poi: day.pois[i]),
                              if (i < day.pois.length - 1 &&
                                  i < day.transitLegs.length)
                                _TransitLegRow(leg: day.transitLegs[i]),
                            ],
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 6),
                          if (itinerary.sources.isNotEmpty)
                            _SourcesCard(sources: itinerary.sources),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _exportJson(context, itinerary),
                              icon: const Icon(Icons.download_rounded,
                                  size: 18, color: kMint),
                              label: Text('Export Itinerary JSON',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: kMint)),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                side:
                                    const BorderSide(color: kMint, width: 1.5),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.pushNamed(
                                  context, '/user-selection'),
                              icon:
                                  const Icon(Icons.checklist_rounded, size: 18),
                              label: const Text('Select My Stops'),
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

class _DayHeader extends StatelessWidget {
  final ItineraryDay day;
  const _DayHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: kMint, borderRadius: BorderRadius.circular(50)),
          child: Text('Day ${day.day}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(day.theme,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
        ),
        if (day.estimatedCost.isNotEmpty) ...[
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(day.estimatedCost,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: kSubtext)),
          ),
        ],
      ]),
    );
  }
}

class _PoiRow extends StatelessWidget {
  final int sequence;
  final Poi poi;
  const _PoiRow({required this.sequence, required this.poi});

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the Korean name inside "(...)" for the map search; fall back to
    // the full place name when there's no parenthesised text.
    final paren = RegExp(r'[（(]([^）)]+)[）)]').firstMatch(poi.name);
    final term = paren?.group(1)?.trim();
    final keyword = Uri.encodeQueryComponent(
        (term != null && term.isNotEmpty) ? term : poi.name);
    final naverUrl =
        'https://m.map.naver.com/search2/search.naver?query=$keyword';
    final kakaoUrl = 'https://map.kakao.com/?q=$keyword';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: kMintLight, borderRadius: BorderRadius.circular(10)),
              child: Center(
                child: Text('$sequence',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: kMint)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(poi.name,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kInk)),
                    if (poi.address.isNotEmpty)
                      Text(poi.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: kSubtext)),
                  ]),
            ),
            if (poi.type.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: kMintLight, borderRadius: BorderRadius.circular(20)),
                child: Text(poi.type,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kMint)),
              ),
          ]),
          const SizedBox(height: 10),
          // Per-POI map search links: Naver + Kakao, by place title.
          Row(children: [
            const SizedBox(width: 46),
            _MapSearchButton(
              label: 'Naver Map',
              bg: const Color(0xFF03C75A),
              onTap: () => _open(naverUrl),
            ),
            const SizedBox(width: 8),
            _MapSearchButton(
              label: 'Kakao Map',
              bg: const Color(0xFFFFE000),
              fg: Colors.black,
              onTap: () => _open(kakaoUrl),
            ),
          ]),
        ],
      ),
    );
  }
}

/// A small pill button + hyperlink that opens a map search for a POI title.
class _MapSearchButton extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  const _MapSearchButton({
    required this.label,
    required this.bg,
    this.fg = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.map_outlined, size: 13, color: fg),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
            const SizedBox(width: 3),
            Icon(Icons.open_in_new, size: 10, color: fg.withValues(alpha: 0.8)),
          ]),
        ),
      ),
    );
  }
}

/// One leg between two consecutive stops on the itinerary map: distance /
/// walk / car chips and a Kakao Map deep-link. Public-transit (ODsay) options
/// live on the Transit screen, not here.
class _TransitLegRow extends StatelessWidget {
  final TransitLeg leg;
  const _TransitLegRow({required this.leg});

  @override
  Widget build(BuildContext context) {
    if (!leg.hasAnyData) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 17, bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 2, color: kMint.withValues(alpha: 0.3)),
            const SizedBox(width: 14),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (leg.distanceKm != null)
                    _LegChip(
                      icon: Icons.straighten,
                      label: '${leg.distanceKm!.toStringAsFixed(1)} km',
                    ),
                  if (leg.walkMinutes != null)
                    _LegChip(emoji: '🚶', label: '${leg.walkMinutes} min'),
                  if (leg.carMinutes != null)
                    _LegChip(emoji: '🚗', label: '${leg.carMinutes} min'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegChip extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final String label;

  const _LegChip({this.icon, this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kInk.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 12)),
          if (icon != null) Icon(icon, size: 13, color: kSubtext),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kSubtext,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcesCard extends StatelessWidget {
  final List<ItinerarySource> sources;
  const _SourcesCard({required this.sources});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.shield_rounded, size: 14, color: kMint),
            const SizedBox(width: 6),
            Text('Verified Sources',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in sources)
                _SourceBadge(
                    s.courseTitle.isNotEmpty ? s.courseTitle : s.source),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String label;
  const _SourceBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kCanvas,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kMint.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, size: 11, color: kMint),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, fontWeight: FontWeight.w600, color: kInk)),
        ),
      ]),
    );
  }
}
