import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../models/travel_state.dart';
import '../providers/travel_provider.dart';
import '../services/api_service.dart';

class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({super.key});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  late final List<Poi> _pois;
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _pois = context.read<TravelProvider>().allPois;
    // Pre-select every stop.
    _selected = Set<int>.from(List.generate(_pois.length, (i) => i));
  }

  int get _selectedCount => _selected.length;

  void _toggle(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  void _buildRoute() {
    // Pass selected POIs in original itinerary order.
    final stops = [
      for (var i = 0; i < _pois.length; i++)
        if (_selected.contains(i)) _pois[i],
    ];
    context.read<TravelProvider>().setSelectedStops(stops);
    Navigator.pushNamed(context, '/route-variation');
  }

  @override
  Widget build(BuildContext context) {
    if (_pois.isEmpty) {
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
                      '$_selectedCount / ${_pois.length}',
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
                  for (var i = 0; i < _pois.length; i++) ...[
                    if (_pois[i].day > 0 &&
                        (i == 0 || _pois[i].day != _pois[i - 1].day))
                      _DaySectionHeader(day: _pois[i].day),
                    _SelectionCard(
                      poi: _pois[i],
                      selected: _selected.contains(i),
                      onChanged: (_) => _toggle(i),
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
                    child: ElevatedButton.icon(
                      onPressed: _selectedCount >= 2 ? _buildRoute : null,
                      icon: const Icon(Icons.route_rounded, size: 18),
                      label: Text('Build My Route ($_selectedCount stops)'),
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

class _SelectionCard extends StatefulWidget {
  final Poi poi;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _SelectionCard({
    required this.poi,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<_SelectionCard> createState() => _SelectionCardState();
}

class _SelectionCardState extends State<_SelectionCard> {
  Future<String>? _detailFuture;
  bool _explainExpanded = false;

  void _onExplain() {
    setState(() {
      _explainExpanded = true;
      _detailFuture ??= ApiService().fetchPoiDetail(
        widget.poi.name,
        type: widget.poi.type,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final poi = widget.poi;
    final subtitle = poi.address.isNotEmpty
        ? poi.address
        : (poi.stayMinutes > 0 ? '${poi.stayMinutes} min stay' : '');

    return GestureDetector(
      onTap: () => widget.onChanged(!widget.selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.selected ? kCard : kCanvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.selected ? kMint : kCardBorder,
            width: widget.selected ? 1.5 : 1,
          ),
          boxShadow: widget.selected
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
            // Selection checkbox
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.selected
                    ? Container(
                        key: const ValueKey('checked'),
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                            color: kMint, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            size: 18, color: Colors.white),
                      )
                    : Container(
                        key: const ValueKey('unchecked'),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: kCardBorder, width: 2),
                          color: kCanvas,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // POI name + type badge
                  Row(children: [
                    Expanded(
                      child: Text(poi.name,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kInk)),
                    ),
                    if (poi.type.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
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
                    // Mascot + existing notes as speech bubble (no extra API call)
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
                              border: Border.all(
                                  color: kYellow.withValues(alpha: 0.6)),
                            ),
                            child: Text(poi.notes,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: kInk,
                                    height: 1.5)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Explain button (absorbs tap so it doesn't toggle selection)
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
                  // Tavily detail — lazy, only fetched after Explain tap
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
                                    fontSize: 11,
                                    color: kSubtext,
                                    height: 1.6)),
                          ),
                        );
                      },
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
