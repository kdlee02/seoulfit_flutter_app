import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/trip_checkin.dart';
import '../providers/travel_provider.dart';
import '../services/checkin_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';

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
    final trip = await CheckinStore.load(context.read<TravelProvider>().tripId);
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
            const SizedBox(height: 20),
            for (final day in trip.plannedDays) ...[
              _DayRow(
                day: day,
                tier: trip.stampFor(day),
                visited: trip.checkins[day]?.visited
                        .where((n) => trip.planned[day]!.contains(n))
                        .length ??
                    0,
                planned: trip.planned[day]?.length ?? 0,
                recorded: trip.checkins.containsKey(day),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
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

class _DayRow extends StatelessWidget {
  final int day;
  final StampTier tier;
  final int visited;
  final int planned;
  final bool recorded;

  const _DayRow({
    required this.day,
    required this.tier,
    required this.visited,
    required this.planned,
    required this.recorded,
  });

  @override
  Widget build(BuildContext context) {
    // The stamp is decoration; the exact fraction next to it is the real record.
    final opacity = switch (tier) {
      StampTier.full => 1.0,
      StampTier.faded => 0.35,
      StampTier.none => 0.0,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: opacity,
            child: const Icon(Icons.verified_rounded, color: kMint, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Day $day',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
          ),
          Text(
            recorded ? '$planned곳 중 $visited곳' : '미기록',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: recorded ? kInk : kSubtext,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
