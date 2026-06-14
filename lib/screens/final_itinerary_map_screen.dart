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
import '../services/api_service.dart';

class FinalItineraryMapScreen extends StatefulWidget {
  const FinalItineraryMapScreen({super.key});

  @override
  State<FinalItineraryMapScreen> createState() =>
      _FinalItineraryMapScreenState();
}

class _FinalItineraryMapScreenState extends State<FinalItineraryMapScreen> {
  int? _selectedDay;

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
      if (context.mounted) _snack(context, 'Itinerary saved as JSON', kSuccess);
    } catch (e) {
      if (context.mounted) _snack(context, 'Save failed: $e', Colors.red);
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

  Widget _dayPills(List<ItineraryDay> days) {
    if (days.length <= 1) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final d in days)
            GestureDetector(
              onTap: () => setState(() => _selectedDay = d.day),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: d.day == _selectedDay ? kMint : Colors.transparent,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: d.day == _selectedDay ? kMint : kCardBorder,
                  ),
                ),
                child: Text(
                  'Day ${d.day}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: d.day == _selectedDay ? Colors.white : kSubtext,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: kSubtext)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, '/chat', (r) => false),
                child: const Text('Go to Chat'),
              ),
              const Spacer(),
              const AppBottomNav(currentIndex: 1),
            ],
          ),
        ),
      );
    }

    final days = itinerary.days;
    final activeDay = days.firstWhere(
      (d) => d.day == _selectedDay,
      orElse: () => days.first,
    );
    if (_selectedDay != activeDay.day) _selectedDay = activeDay.day;

    final totalStops = itinerary.days.fold<int>(0, (n, d) => n + d.pois.length);
    final score = _score(itinerary);

    final mapItinerary = Itinerary(
      summary: itinerary.summary,
      days: [activeDay],
      sources: itinerary.sources,
      raw: itinerary.raw,
    );

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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: ItineraryMap(itinerary: mapItinerary, height: 260),
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
                                  'Initial Itinerary',
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
                                        color:
                                            kSuccess.withValues(alpha: 0.4)),
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
                            '$totalStops locations · ${days.length} ${days.length == 1 ? "day" : "days"}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13, color: kSubtext),
                          ),
                          if (itinerary.summary.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              itinerary.summary,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13, color: kInk, height: 1.45),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _dayPills(days),
                          if (days.length > 1) const SizedBox(height: 14),
                          _DayHeader(day: activeDay),
                          for (var i = 0; i < activeDay.pois.length; i++) ...[
                            _PoiRow(
                                key: ValueKey('${activeDay.day}-$i'),
                                sequence: i + 1,
                                poi: activeDay.pois[i]),
                            if (i < activeDay.pois.length - 1 &&
                                i < activeDay.transitLegs.length)
                              _TransitLegRow(
                                  leg: activeDay.transitLegs[i]),
                          ],
                          const SizedBox(height: 10),
                          if (itinerary.sources.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _SourcesCard(sources: itinerary.sources),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _exportJson(context, itinerary),
                              icon: const Icon(Icons.download_rounded,
                                  size: 18, color: kMint),
                              label: Text('Export Itinerary JSON',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: kMint)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 15),
                                side: const BorderSide(
                                    color: kMint, width: 1.5),
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
                              icon: const Icon(Icons.checklist_rounded,
                                  size: 18),
                              label: const Text('Select My Stops'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kMint,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50)),
                                elevation: 0,
                                textStyle: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15),
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

class _PoiRow extends StatefulWidget {
  final int sequence;
  final Poi poi;
  const _PoiRow({super.key, required this.sequence, required this.poi});

  @override
  State<_PoiRow> createState() => _PoiRowState();
}

class _PoiRowState extends State<_PoiRow> {
  late final Future<String> _summaryFuture;
  late final Future<String> _imageFuture;

  @override
  void initState() {
    super.initState();
    final svc = ApiService();
    _summaryFuture = svc.fetchPoiSummary(
      widget.poi.name,
      type: widget.poi.type,
    );
    _imageFuture = svc.fetchPoiImage(
      widget.poi.name,
      type: widget.poi.type,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // POI image
          FutureBuilder<String>(
            future: _imageFuture,
            builder: (context, snap) {
              final url = snap.data ?? '';
              if (url.isEmpty) return const SizedBox.shrink();
              return Image.network(
                url,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(13),
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
                      child: Text('${widget.sequence}',
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
                          Text(widget.poi.name,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: kInk)),
                          if (widget.poi.address.isNotEmpty)
                            Text(widget.poi.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: kSubtext)),
                        ]),
                  ),
                  if (widget.poi.type.isNotEmpty)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: kMintLight, borderRadius: BorderRadius.circular(20)),
                      child: Text(widget.poi.type,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: kMint)),
                    ),
                ]),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: FutureBuilder<String>(
                    future: _summaryFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Row(children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: kMint),
                          ),
                          const SizedBox(width: 8),
                          Text('Loading summary…',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11, color: kSubtext)),
                        ]);
                      }
                      final summary = snap.data ?? '';
                      if (summary.isEmpty) return const SizedBox.shrink();
                      return Text(
                        summary,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: kSubtext, height: 1.5),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
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
                  label: s.courseTitle.isNotEmpty ? s.courseTitle : s.source,
                  url: s.sourceUrl,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String label;
  final String url;
  const _SourceBadge({required this.label, required this.url});

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = url.isNotEmpty;
    final badge = Container(
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
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hasUrl ? kMint : kInk,
                  decoration: hasUrl ? TextDecoration.underline : null,
                  decorationColor: kMint)),
        ),
        if (hasUrl) ...[
          const SizedBox(width: 3),
          const Icon(Icons.open_in_new, size: 10, color: kMint),
        ],
      ]),
    );
    if (!hasUrl) return badge;
    return GestureDetector(onTap: _open, child: badge);
  }
}
