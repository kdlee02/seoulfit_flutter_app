import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/trip_checkin.dart';
import '../providers/travel_provider.dart';
import '../services/checkin_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';

const _reasonLabels = {
  MissReason.time: '시간 부족',
  MissReason.stamina: '체력 부족',
  MissReason.notInterested: '마음이 안 감',
  MissReason.other: '기타',
};

/// One day at a time: tick what you visited, and say why for the rest.
/// Opens on the first day that has no record yet.
class TripCheckinScreen extends StatefulWidget {
  const TripCheckinScreen({super.key});

  @override
  State<TripCheckinScreen> createState() => _TripCheckinScreenState();
}

class _TripCheckinScreenState extends State<TripCheckinScreen> {
  TripCheckin? _trip;
  int _day = 1;
  Set<String> _visited = {};
  Map<String, MissReason> _misses = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final provider = context.read<TravelProvider>();
    final tripId = provider.tripId;
    // Load an existing record, or snapshot the confirmed selection into a new
    // one. selectedStops is memory-only, so this snapshot is what later days
    // measure against.
    var trip = await CheckinStore.load(tripId);
    trip ??= TripCheckin.fromStops(
      tripId,
      provider.selectedStops.isNotEmpty
          ? provider.selectedStops
          : provider.allPois,
      provider.itinerary?.feasibilityScore,
    );
    final days = trip.plannedDays;
    final firstUnchecked =
        days.firstWhere((d) => !trip!.checkins.containsKey(d), orElse: () => days.isEmpty ? 1 : days.first);
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _day = firstUnchecked;
      _loading = false;
    });
    _loadDay(firstUnchecked);
  }

  void _loadDay(int day) {
    final entry = _trip?.checkins[day];
    setState(() {
      _day = day;
      _visited = {...?entry?.visited};
      _misses = {...?entry?.misses};
    });
  }

  void _toggle(String name) {
    setState(() {
      if (_visited.remove(name)) return;
      _visited.add(name);
      _misses.remove(name);
    });
  }

  Future<void> _saveDay() async {
    final trip = _trip;
    if (trip == null) return;
    final stops = trip.planned[_day] ?? const <String>[];
    // Anything not ticked is a miss; default to "other" if no reason was given.
    final misses = <String, MissReason>{
      for (final name in stops)
        if (!_visited.contains(name)) name: _misses[name] ?? MissReason.other,
    };
    final updated = trip.withDay(
      _day,
      DayCheckin(visited: {..._visited}, misses: misses),
    );
    await CheckinStore.save(updated);
    if (!mounted) return;
    setState(() => _trip = updated);
    Navigator.pushNamed(context, '/trip-recap');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kCanvas,
        body: Center(child: CircularProgressIndicator(color: kMint)),
      );
    }
    final trip = _trip!;
    final stops = trip.planned[_day] ?? const <String>[];
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppStatusBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('오늘 다녀오셨나요?',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('다녀온 곳을 눌러서 체크하세요. 안 누른 곳은 이유를 골라주세요.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: kSubtext)),
            ),
            if (trip.plannedDays.length > 1)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final d in trip.plannedDays)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('Day $d'),
                          selected: d == _day,
                          selectedColor: kMintLight,
                          onSelected: (_) => _loadDay(d),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                itemCount: stops.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final name = stops[i];
                  final visited = _visited.contains(name);
                  return _StopTile(
                    name: name,
                    visited: visited,
                    reason: _misses[name],
                    onToggle: () => _toggle(name),
                    onReason: (r) => setState(() => _misses[name] = r),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: stops.isEmpty ? null : _saveDay,
                  child: Text('Day $_day 기록하기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  final String name;
  final bool visited;
  final MissReason? reason;
  final VoidCallback onToggle;
  final ValueChanged<MissReason> onReason;

  const _StopTile({
    required this.name,
    required this.visited,
    required this.reason,
    required this.onToggle,
    required this.onReason,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: visited ? kMint : kCardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(
                  visited
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: visited ? kSuccess : kSubtext,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kInk)),
                ),
              ],
            ),
          ),
          if (!visited) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in _reasonLabels.entries)
                  ChoiceChip(
                    label: Text(entry.value,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    selected: reason == entry.key,
                    selectedColor: kMintLight,
                    onSelected: (_) => onReason(entry.key),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
