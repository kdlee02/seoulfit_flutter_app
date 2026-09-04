import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../models/travel_state.dart';
import '../providers/travel_provider.dart';
import '../services/api_service.dart';

/// Whether a slot is showing the itinerary's original pick, has been swapped
/// for a candidate, or has been removed from the route (slot stays, content
/// doesn't count toward the trip).
enum SlotStatus { kept, excluded, swapped }

/// One fixed position in the flattened itinerary. The slot itself never
/// disappears — only [status]/[currentPoi] change — so a user can always
/// undo back to [originalPoi] and the day/position bookkeeping never drifts.
class SlotState {
  final int slotIndex;
  final Poi originalPoi;
  Poi currentPoi;
  SlotStatus status;
  bool userTouched;

  SlotState({
    required this.slotIndex,
    required this.originalPoi,
    Poi? currentPoi,
    this.status = SlotStatus.kept,
    this.userTouched = false,
  }) : currentPoi = currentPoi ?? originalPoi;
}

/// Straight-line distance between two coordinates (Haversine). Used only for
/// the swap-candidate "how far is this from what's here now" hint — not a
/// routed distance, so it's presented as an estimate.
double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

/// ~4.8 km/h average walking pace, matching the rough estimate the rest of
/// the app uses before a real routed leg is available.
int _walkMinutesEstimate(double km) => (km / 4.8 * 60).round();

class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({super.key});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  late final List<SlotState> _slots;

  /// Composed swap tracking: {name the backend's persisted itinerary still
  /// has for this slot -> name we want it to become}. Swapping the same slot
  /// twice before tapping Check composes into one entry (A->C, not A->B then
  /// a dangling B->C the backend has never seen) so /revalidate always
  /// matches against what's actually persisted. Cleared after a successful
  /// check, since the backend then has the new names.
  final Map<String, String> _pendingSwaps = {};

  bool _checking = false;

  @override
  void initState() {
    super.initState();
    final pois = context.read<TravelProvider>().allPois;
    _slots = [
      for (var i = 0; i < pois.length; i++)
        SlotState(slotIndex: i, originalPoi: pois[i]),
    ];
  }

  int get _keptCount =>
      _slots.where((s) => s.status != SlotStatus.excluded).length;

  void _toggleExclude(SlotState slot) {
    setState(() {
      slot.status = slot.status == SlotStatus.excluded
          ? (slot.currentPoi.name == slot.originalPoi.name
              ? SlotStatus.kept
              : SlotStatus.swapped)
          : SlotStatus.excluded;
      slot.userTouched = true;
    });
  }

  void _applySwap(SlotState slot, Poi candidate) {
    setState(() {
      // If this slot was already swapped once this session (backend hasn't
      // seen it yet), compose onto that entry's key instead of adding a
      // dangling one the backend has no matching name for.
      var backendKnownName = slot.currentPoi.name;
      for (final entry in _pendingSwaps.entries) {
        if (entry.value == slot.currentPoi.name) {
          backendKnownName = entry.key;
          break;
        }
      }
      _pendingSwaps[backendKnownName] = candidate.name;
      slot.currentPoi = candidate;
      slot.status = SlotStatus.swapped;
      slot.userTouched = true;
    });
  }

  /// Every currently-visible POI name across all slots — passed as
  /// excluded_ids to /swap-candidates so a candidate already sitting in
  /// another slot never gets suggested twice.
  List<String> get _allCurrentNames =>
      [for (final s in _slots) s.currentPoi.name];

  String _dayAreaFor(SlotState slot) {
    final area = slot.currentPoi.area ?? slot.originalPoi.area;
    if (area != null && area.isNotEmpty) return area;
    // Fallback for older itineraries the backend hasn't re-tagged with
    // `area` yet: take the first requested region off the trip state.
    final region = context.read<TravelProvider>().state?.region ?? '';
    final first = region.split(RegExp(r'[,(]')).first.trim().toLowerCase();
    return first;
  }

  Future<void> _runCheck() async {
    setState(() => _checking = true);
    final provider = context.read<TravelProvider>();
    try {
      final excludedIds = [
        for (final s in _slots)
          if (s.status == SlotStatus.excluded) s.currentPoi.name,
      ];
      final result = await provider.revalidate(
        excludedIds: excludedIds,
        swappedSlots: Map.of(_pendingSwaps),
      );
      _pendingSwaps.clear();
      if (!mounted) return;
      await _showDiagnosticSheet(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Check failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showDiagnosticSheet(Map<String, dynamic> result) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DiagnosticSheet(
        before: (result['before'] as Map?)?.cast<String, dynamic>() ?? const {},
        after: (result['after'] as Map?)?.cast<String, dynamic>() ?? const {},
        repairLog: (result['repair_log'] as List?)?.cast<dynamic>() ?? const [],
      ),
    );
  }

  void _buildRoute() {
    final stops = [
      for (final s in _slots)
        if (s.status != SlotStatus.excluded) s.currentPoi,
    ];
    context.read<TravelProvider>().setSelectedStops(stops);
    Navigator.pushNamed(context, '/route-variation');
  }

  @override
  Widget build(BuildContext context) {
    if (_slots.isEmpty) {
      return Scaffold(
        backgroundColor: kCanvas,
        body: SafeArea(
          child: Column(
            children: [
              const AppStatusBar(),
              const Spacer(),
              const Icon(Icons.checklist_rounded, size: 48, color: kSubtext),
              const SizedBox(height: 12),
              Text('No stops to select',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 6),
              Text('Plan a trip first to choose your stops.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: kSubtext)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/chat'),
                child: const Text('Go to Chat'),
              ),
              const Spacer(),
              const AppBottomNav(currentIndex: 1),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            Container(
              color: kCard,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Select Your Stops',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: kInk)),
                        Text('Pick the places you want to visit',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12, color: kSubtext)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: kMint,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      '$_keptCount / ${_slots.length}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  for (var i = 0; i < _slots.length; i++) ...[
                    if (_slots[i].originalPoi.day > 0 &&
                        (i == 0 ||
                            _slots[i].originalPoi.day !=
                                _slots[i - 1].originalPoi.day))
                      _DaySectionHeader(day: _slots[i].originalPoi.day),
                    _SelectionCard(
                      key: ValueKey(
                          '${_slots[i].slotIndex}-${_slots[i].currentPoi.name}'),
                      slot: _slots[i],
                      dayArea: _dayAreaFor(_slots[i]),
                      excludedIds: _allCurrentNames,
                      onToggleExclude: () => _toggleExclude(_slots[i]),
                      onSwap: (candidate) => _applySwap(_slots[i], candidate),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            Container(
              color: kCard,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _checking ? null : _runCheck,
                      icon: _checking
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fact_check_rounded, size: 18),
                      label: Text(_checking ? 'Checking…' : 'Check My Plan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kMint,
                        side: const BorderSide(color: kMint, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50)),
                        textStyle: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _keptCount >= 2 ? _buildRoute : null,
                      icon: const Icon(Icons.route_rounded, size: 18),
                      label: Text('Build My Route ($_keptCount stops)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kMint,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: kCardBorder,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50)),
                        elevation: 0,
                        textStyle: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const AppBottomNav(currentIndex: 1),
          ],
        ),
      ),
    );
  }
}

/// Day divider in the stop list so Day 1 and Day 2 stops are visually grouped
/// instead of running together as one undivided list.
class _DaySectionHeader extends StatelessWidget {
  final int day;
  const _DaySectionHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: kMint,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text('Day $day',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: kCardBorder, height: 1)),
        ],
      ),
    );
  }
}

/// Paints a dashed rounded-rect border — Flutter's [Border] has no dashed
/// style built in and the project doesn't depend on a dotted-border package,
/// so this is the whole implementation rather than a new dependency for one
/// visual state.
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRRectPainter({required this.color, this.radius = 16});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const dashWidth = 5.0;
    const gapWidth = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _SelectionCard extends StatefulWidget {
  final SlotState slot;
  final String dayArea;
  final List<String> excludedIds;
  final VoidCallback onToggleExclude;
  final ValueChanged<Poi> onSwap;

  const _SelectionCard({
    super.key,
    required this.slot,
    required this.dayArea,
    required this.excludedIds,
    required this.onToggleExclude,
    required this.onSwap,
  });

  @override
  State<_SelectionCard> createState() => _SelectionCardState();
}

class _SelectionCardState extends State<_SelectionCard> {
  Future<String>? _detailFuture;
  bool _explainExpanded = false;

  bool _swapExpanded = false;
  Future<List<Map<String, dynamic>>>? _swapCandidatesFuture;

  void _onExplain() {
    setState(() {
      _explainExpanded = true;
      _detailFuture ??= ApiService().fetchPoiDetail(
        widget.slot.currentPoi.name,
        type: widget.slot.currentPoi.type,
      );
    });
  }

  void _onSwapTap() {
    setState(() {
      _swapExpanded = !_swapExpanded;
      if (_swapExpanded) {
        final poi = widget.slot.currentPoi;
        _swapCandidatesFuture = context.read<TravelProvider>().fetchSwapCandidates(
              day: widget.slot.originalPoi.day,
              slotIndex: widget.slot.slotIndex,
              currentPoi: poi.name,
              dayArea: widget.dayArea,
              currentPoiType: poi.type,
              excludedIds: widget.excludedIds,
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final poi = slot.currentPoi;
    final excluded = slot.status == SlotStatus.excluded;
    final swapped = slot.status == SlotStatus.swapped;
    final subtitle = poi.address.isNotEmpty
        ? poi.address
        : (poi.stayMinutes > 0 ? '${poi.stayMinutes} min stay' : '');

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: excluded ? kCanvas : kCard,
        borderRadius: BorderRadius.circular(16),
        border: excluded
            ? null // dashed border painted separately below
            : Border.all(
                color: swapped ? kMint : kCardBorder,
                width: swapped ? 1.5 : 1,
              ),
        boxShadow: swapped
            ? [
                BoxShadow(
                    color: kMint.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 3))
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // POI name + type badge (+ swapped badge)
                Row(children: [
                  Expanded(
                    child: Text(poi.name,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kInk)),
                  ),
                  if (swapped)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: kMint, borderRadius: BorderRadius.circular(20)),
                      child: Text('Swapped',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  if (poi.type.isNotEmpty)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: kMintLight,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(poi.type,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: kMint)),
                    ),
                ]),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: kSubtext)),
                ],
                if (poi.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset('assets/images/seoulfit_mascot.png',
                          width: 38, height: 38),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: kYellowLight,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(12),
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                            border:
                                Border.all(color: kYellow.withValues(alpha: 0.6)),
                          ),
                          child: Text(poi.notes,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11, color: kInk, height: 1.5)),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                // Explain + Swap action row (absorbs taps so they don't hit
                // the card's own tap target — there is none anymore; see the
                // trailing checkbox/undo control instead).
                if (!excluded)
                  Row(children: [
                    if (!_explainExpanded)
                      GestureDetector(
                        onTap: _onExplain,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: kMintLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.travel_explore_rounded,
                                size: 12, color: kMint),
                            const SizedBox(width: 4),
                            Text('Explain',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: kMint)),
                          ]),
                        ),
                      ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _onSwapTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _swapExpanded ? kMint : kMintLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.swap_horiz_rounded,
                              size: 13,
                              color: _swapExpanded ? Colors.white : kMint),
                          const SizedBox(width: 4),
                          Text('Swap',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _swapExpanded ? Colors.white : kMint)),
                        ]),
                      ),
                    ),
                  ]),
                if (_explainExpanded)
                  FutureBuilder<String>(
                    future: _detailFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: kMint),
                            ),
                            const SizedBox(width: 6),
                            Text('Searching the web…',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: kSubtext)),
                          ]),
                        );
                      }
                      final detail = snap.data ?? '';
                      if (detail.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kCanvas,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: kCardBorder),
                          ),
                          child: Text(detail,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11, color: kSubtext, height: 1.6)),
                        ),
                      );
                    },
                  ),
                if (_swapExpanded)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _SwapCandidateList(
                      future: _swapCandidatesFuture!,
                      fromPoi: poi,
                      onSelect: (candidate) {
                        widget.onSwap(candidate);
                        setState(() => _swapExpanded = false);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: excluded
                ? OutlinedButton(
                    onPressed: widget.onToggleExclude,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kSubtext,
                      side: const BorderSide(color: kCardBorder),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('되돌리기',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  )
                : GestureDetector(
                    onTap: widget.onToggleExclude,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        key: const ValueKey('checked'),
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                            color: kMint, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );

    if (!excluded) return card;

    return Opacity(
      opacity: 0.4,
      child: CustomPaint(
        painter: const _DashedRRectPainter(color: kSubtext),
        child: card,
      ),
    );
  }
}

/// Renders the up to 3 replacement candidates for a card's Swap expansion —
/// a radio-style list, each row tappable to confirm that candidate.
class _SwapCandidateList extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final Poi fromPoi;
  final ValueChanged<Poi> onSelect;

  const _SwapCandidateList({
    required this.future,
    required this.fromPoi,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Row(children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: kMint),
            ),
            const SizedBox(width: 6),
            Text('Finding alternatives…',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: kSubtext)),
          ]);
        }
        if (snap.hasError) {
          return Text('Could not load alternatives.',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: kSubtext));
        }
        final candidates = snap.data ?? const [];
        if (candidates.isEmpty) {
          return Text('No alternatives found nearby.',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: kSubtext));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in candidates) ...[
              _CandidateRow(candidate: c, fromPoi: fromPoi, onTap: onSelect),
              const SizedBox(height: 6),
            ],
          ],
        );
      },
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final Map<String, dynamic> candidate;
  final Poi fromPoi;
  final ValueChanged<Poi> onTap;

  const _CandidateRow({
    required this.candidate,
    required this.fromPoi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = (candidate['poi_name'] as String?) ?? '';
    final type = (candidate['poi_type'] as String?) ?? '';
    final address = (candidate['address'] as String?) ?? '';
    final lat = (candidate['lat'] as num?)?.toDouble();
    final lng = (candidate['lng'] as num?)?.toDouble();
    final rating = (candidate['rating'] as num?)?.toDouble();
    final warnings = (candidate['warnings'] as List?)?.cast<String>() ?? const [];

    String? distanceLabel;
    if (lat != null && lng != null && fromPoi.lat != null && fromPoi.lng != null) {
      final km = _haversineKm(fromPoi.lat!, fromPoi.lng!, lat, lng);
      final minutes = _walkMinutesEstimate(km);
      distanceLabel = '${km.toStringAsFixed(1)}km · ~$minutes min walk (est.)';
    }

    return GestureDetector(
      onTap: () => onTap(Poi(
        name: name,
        type: type,
        address: address,
        lat: lat,
        lng: lng,
        stayMinutes: fromPoi.stayMinutes,
        notes: '',
        area: candidate['area'] as String? ?? fromPoi.area,
        day: fromPoi.day,
      )),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: kCanvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kCardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.radio_button_unchecked_rounded,
                  size: 16, color: kSubtext),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: kInk)),
                    ),
                    if (rating != null) ...[
                      const Icon(Icons.star_rounded, size: 12, color: kYellow),
                      const SizedBox(width: 2),
                      Text(rating.toStringAsFixed(1),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: kSubtext)),
                    ],
                  ]),
                  if (address.isNotEmpty || distanceLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (address.isNotEmpty) address,
                        if (distanceLabel != null) distanceLabel,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10, color: kSubtext),
                    ),
                  ],
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final w in warnings)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: kYellowLight,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: kYellow.withValues(alpha: 0.6)),
                            ),
                            child: Text('⚠ $w',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: kInk)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// POST /revalidate diagnostic — feasibility before/after, plus every issue
/// found. Issues present in `before` but gone from `after` were auto-fixed by
/// RepairAgent already; issues still in `after` are what repair couldn't fix
/// on its own.
class _DiagnosticSheet extends StatefulWidget {
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final List<dynamic> repairLog;

  const _DiagnosticSheet({
    required this.before,
    required this.after,
    required this.repairLog,
  });

  @override
  State<_DiagnosticSheet> createState() => _DiagnosticSheetState();
}

class _DiagnosticSheetState extends State<_DiagnosticSheet> {
  final Set<String> _dismissed = {};

  static String _issueKey(Map issue) =>
      '${issue['code']}|${issue['day']}|${issue['area']}';

  /// Issue codes this app currently produces are pure structural checks
  /// (area coverage, day size, duplicates, ...) — none of them come from a
  /// live web search. CLOSED_ON_ASSIGNED_DAY (closed_weekday, Google Places)
  /// and any closure_check.py-sourced code are both anticipated here so the
  /// right caveat appears the moment those rules exist, without another
  /// Flutter change.
  bool _isSearchSourced(Map issue) {
    final code = (issue['code'] ?? '').toString().toUpperCase();
    return code.contains('TEMP_CLOSURE') ||
        code.contains('CLOSURE_CHECK') ||
        code.contains('GROUNDING');
  }

  @override
  Widget build(BuildContext context) {
    final beforeScore = (widget.before['overall_score'] as num?)?.toDouble();
    final afterScore = (widget.after['overall_score'] as num?)?.toDouble();

    final beforeIssues =
        (widget.before['issues'] as List? ?? const []).cast<Map>();
    final afterIssues =
        (widget.after['issues'] as List? ?? const []).cast<Map>();
    final afterKeys = afterIssues.map(_issueKey).toSet();
    final resolved =
        beforeIssues.where((i) => !afterKeys.contains(_issueKey(i))).toList();
    final remaining =
        afterIssues.where((i) => !_dismissed.contains(_issueKey(i))).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: kCanvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kCardBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: kMintLight,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.verified_rounded,
                              size: 13, color: kMint),
                          const SizedBox(width: 5),
                          Text('Plan Check',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kMint)),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ScoreRow(before: beforeScore, after: afterScore),
                  const SizedBox(height: 20),
                  if (resolved.isNotEmpty) ...[
                    Text('Fixed automatically',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                    const SizedBox(height: 10),
                    for (final issue in resolved)
                      _IssueCard(issue: issue, resolved: true),
                    const SizedBox(height: 20),
                  ],
                  if (remaining.isNotEmpty) ...[
                    Text('Still needs your attention',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                    const SizedBox(height: 10),
                    for (final issue in remaining)
                      _IssueCard(
                        issue: issue,
                        resolved: false,
                        searchSourced: _isSearchSourced(issue),
                        onApply: () =>
                            setState(() => _dismissed.add(_issueKey(issue))),
                        onDismiss: () =>
                            setState(() => _dismissed.add(_issueKey(issue))),
                      ),
                    const SizedBox(height: 20),
                  ],
                  if (resolved.isEmpty && remaining.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kCardBorder),
                      ),
                      child: Row(children: [
                        const Icon(Icons.celebration_rounded,
                            size: 18, color: kMint),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('No issues found — your plan looks solid.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12, color: kInk)),
                        ),
                      ]),
                    ),
                  if (widget.repairLog.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('What changed',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                    const SizedBox(height: 10),
                    for (var i = 0; i < widget.repairLog.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
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
                                  child: Text('${i + 1}',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: kMint)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('${widget.repairLog[i]}',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12, color: kSubtext, height: 1.5)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kMint,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50)),
                        elevation: 0,
                        textStyle: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final double? before;
  final double? after;
  const _ScoreRow({required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final improved = (before != null && after != null) && after! >= before!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ScorePill(label: 'Before', score: before, highlight: false),
          Icon(Icons.arrow_forward_rounded,
              size: 20, color: improved ? kMint : kSubtext),
          _ScorePill(label: 'After', score: after, highlight: true),
        ],
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  final String label;
  final double? score;
  final bool highlight;
  const _ScorePill({required this.label, required this.score, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final text = score != null ? (score! * 100).round().toString() : '--';
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: kSubtext)),
        const SizedBox(height: 4),
        Text(text,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: highlight ? kMint : kInk)),
      ],
    );
  }
}

class _IssueCard extends StatelessWidget {
  final Map issue;
  final bool resolved;
  final bool searchSourced;
  final VoidCallback? onApply;
  final VoidCallback? onDismiss;

  const _IssueCard({
    required this.issue,
    required this.resolved,
    this.searchSourced = false,
    this.onApply,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final message = (issue['message'] as String?) ?? '';
    final severity = (issue['severity'] as String?) ?? '';
    final sourceUrl = issue['source_url'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(resolved ? '✅' : '⚠️', style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: kInk, height: 1.4)),
              ),
              if (!resolved && severity.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kYellowLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(severity,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 9, fontWeight: FontWeight.w700, color: kInk)),
                ),
            ],
          ),
          if (!resolved && searchSourced) ...[
            const SizedBox(height: 8),
            Text(
              '⚠ Checked via live search — please reconfirm before your visit.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: kSubtext, fontStyle: FontStyle.italic),
            ),
            if (sourceUrl != null && sourceUrl.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(sourceUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: kMint, decoration: TextDecoration.underline)),
            ],
          ],
          if (!resolved && (onApply != null || onDismiss != null)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onApply != null)
                  TextButton(
                    onPressed: onApply,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: kMint,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50)),
                    ),
                    child: Text('적용',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(width: 8),
                if (onDismiss != null)
                  TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: kSubtext,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('무시',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
