import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/trip_checkin.dart';
import '../providers/travel_provider.dart';
import '../services/checkin_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/visited_route_map.dart';

/// Everything recorded so far, rendered from the local store. There is no
/// "finish the trip" step — the recap simply reflects whatever has been
/// checked in, and days with no record are shown as unrecorded rather than
/// counted as failures.
class TripRecapScreen extends StatefulWidget {
  const TripRecapScreen({super.key});

  @override
  State<TripRecapScreen> createState() => _TripRecapScreenState();
}

class _TripRecapScreenState extends State<TripRecapScreen> {
  TripCheckin? _trip;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tripId = context.read<TravelProvider>().tripId;
    // provider.tripId can be a fresh id after an app restart (see
    // CheckinStore.loadActive doc). The recap has no in-memory selection to
    // compare against, so falling back unconditionally is correct here —
    // unlike the check-in screen, there is no "started a genuinely new trip"
    // case to guard against.
    var trip = await CheckinStore.load(tripId);
    trip ??= await CheckinStore.loadActive();
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kCanvas,
        body: Center(child: CircularProgressIndicator(color: kMint)),
      );
    }
    final trip = _trip;
    if (trip == null || trip.checkedDays.isEmpty) {
      return Scaffold(
        backgroundColor: kCanvas,
        body: SafeArea(
          child: Column(
            children: [
              const AppStatusBar(),
              const Spacer(),
              const Icon(Icons.inbox_rounded, size: 44, color: kSubtext),
              const SizedBox(height: 10),
              Text('아직 기록이 없어요',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/trip-checkin'),
                child: const Text('체크인 하러 가기'),
              ),
              const Spacer(),
            ],
          ),
        ),
      );
    }

    final rate = trip.completionRate;
    final stamped = trip.plannedDays
        .where((d) => trip.stampFor(d) != StampTier.none)
        .length;
    final unrecorded = trip.plannedDays.length - trip.checkedDays.length;
    // Empty for records written before coordinates were snapshotted, and for
    // a trip where nothing visited had a location — the rest of the recap
    // still renders in both cases.
    final pointsByDay = {
      for (final day in trip.plannedDays)
        if (trip.visitedPointsFor(day).isNotEmpty)
          day: trip.visitedPointsFor(day),
    };

    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const AppStatusBar(),
            const SizedBox(height: 8),
            Text('여행 기록',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 24, fontWeight: FontWeight.w800, color: kInk)),
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
                  _Stat('완료율',
                      rate == null ? '—' : '${(rate * 100).round()}%'),
                  _Stat('스탬프', '$stamped개'),
                  _Stat('기록한 날', '${trip.checkedDays.length}일'),
                ],
              ),
            ),
            if (unrecorded > 0) ...[
              const SizedBox(height: 10),
              Text('기록하지 않은 날 $unrecorded일은 완료율 계산에서 빠졌어요.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: kSubtext)),
            ],
            if (pointsByDay.isNotEmpty) ...[
              const SizedBox(height: 20),
              VisitedRouteMap(pointsByDay: pointsByDay),
              const SizedBox(height: 12),
              // The stamp is decoration; these fractions are the actual record,
              // so they stay on screen even though the per-day cards are gone.
              _DayLegend(trip: trip),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/trip-story'),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text('스토리용으로 보기',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ] else ...[
              const SizedBox(height: 20),
              _DayLegend(trip: trip),
            ],
          ],
        ),
      ),
    );
  }
}

/// One line per planned day: the day's colour dot, its number, and the exact
/// visited/planned fraction — or 미기록 when it was never checked in.
class _DayLegend extends StatelessWidget {
  final TripCheckin trip;
  const _DayLegend({required this.trip});

  @override
  Widget build(BuildContext context) {
    final drawnDays = trip.plannedDays
        .where((d) => trip.visitedPointsFor(d).isNotEmpty)
        .toList();
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final day in trip.plannedDays)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Only days with a drawn route carry a palette colour; the
                  // index must match VisitedRouteMap's, which skips days that
                  // drew nothing.
                  color: drawnDays.contains(day)
                      ? kDayColors[
                          drawnDays.indexOf(day) % kDayColors.length]
                      : kCardBorder,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _label(day),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: trip.checkins.containsKey(day) ? kInk : kSubtext,
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _label(int day) {
    final stops = trip.planned[day] ?? const <String>[];
    final entry = trip.checkins[day];
    if (entry == null) return 'Day $day 미기록';
    final visited = entry.visited.where(stops.contains).length;
    return 'Day $day $visited/${stops.length}';
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  GoogleFonts.plusJakartaSans(fontSize: 12, color: kSubtext)),
        ],
      );
}
