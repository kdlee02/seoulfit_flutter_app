import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../models/travel_state.dart';
import '../providers/travel_provider.dart';

class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({super.key});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  late final List<Poi> _pois;
  // Stores indices into _pois in the order they were selected.
  late final List<int> _selectionOrder;

  @override
  void initState() {
    super.initState();
    _pois = context.read<TravelProvider>().allPois;
    // Pre-select every stop, in itinerary order.
    _selectionOrder = List<int>.generate(_pois.length, (i) => i);
  }

  int get _selectedCount => _selectionOrder.length;

  void _toggle(int index) {
    setState(() {
      if (_selectionOrder.contains(index)) {
        _selectionOrder.remove(index);
      } else {
        _selectionOrder.add(index);
      }
    });
  }

  int? _orderOf(int index) {
    final pos = _selectionOrder.indexOf(index);
    return pos >= 0 ? pos + 1 : null;
  }

  void _buildRoute() {
    // Hand the selected POIs (in selection order) to the route screen.
    final stops = [for (final i in _selectionOrder) _pois[i]];
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
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: _pois.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  return _SelectionCard(
                    poi: _pois[i],
                    selected: _selectionOrder.contains(i),
                    orderNumber: _orderOf(i),
                    onChanged: (_) => _toggle(i),
                  );
                },
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

class _SelectionCard extends StatelessWidget {
  final Poi poi;
  final bool selected;
  final int? orderNumber;
  final ValueChanged<bool> onChanged;

  const _SelectionCard({
    required this.poi,
    required this.selected,
    this.orderNumber,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasNotes = poi.notes.isNotEmpty;
    final subtitle = poi.address.isNotEmpty
        ? poi.address
        : (poi.stayMinutes > 0 ? '${poi.stayMinutes} min stay' : '');

    return GestureDetector(
      onTap: () => onChanged(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? kCard : kCanvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? kMint : kCardBorder,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: kMint.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 3))
                ]
              : null,
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: orderNumber != null
                  ? Container(
                      key: ValueKey('order_$orderNumber'),
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                          color: kMint, shape: BoxShape.circle),
                      child: Center(
                        child: Text(
                          '$orderNumber',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                      ),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                  if (hasNotes) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kMintLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 11, color: kMint),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            poi.notes,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: kMint,
                            ),
                          ),
                        ),
                      ]),
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
