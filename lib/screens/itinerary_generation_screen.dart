import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/mascot_widget.dart';
import '../providers/travel_provider.dart';

class ItineraryGenerationScreen extends StatefulWidget {
  const ItineraryGenerationScreen({super.key});

  @override
  State<ItineraryGenerationScreen> createState() =>
      _ItineraryGenerationScreenState();
}

class _ItineraryGenerationScreenState extends State<ItineraryGenerationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progress;

  static const _steps = [
    'Connecting to Seoul Course Catalogue...',
    'Searching via FAISS vector index...',
    'Retrieving top-k matched courses...',
    'Ranking by purpose-fit score...',
    'Drafting 1st itinerary...',
  ];
  int _stepIndex = 0;
  bool _generationDone = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4));
    _progress = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _ctrl.forward();
    _ctrl.addListener(() {
      final s =
          (_ctrl.value * _steps.length).floor().clamp(0, _steps.length - 1);
      if (s != _stepIndex) setState(() => _stepIndex = s);
    });
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _maybeProceed();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    final provider = context.read<TravelProvider>();
    // Send the confirmation so the backend runs RAG + planning + critic-repair.
    if (!provider.hasItinerary) {
      await provider.sendMessage('confirm');
    }
    if (!mounted) return;
    _generationDone = true;
    if (!provider.hasItinerary) {
      setState(() => _failed = true);
      return;
    }
    _maybeProceed();
  }

  /// Navigate only once BOTH the animation has finished and the backend has
  /// returned an itinerary — whichever completes last triggers the move.
  void _maybeProceed() {
    if (!mounted) return;
    final provider = context.read<TravelProvider>();
    if (_ctrl.isCompleted && _generationDone && provider.hasItinerary) {
      Navigator.pushReplacementNamed(context, '/critic-repair');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    const MascotWidget(size: 110, variant: MascotVariant.loading),
                    const SizedBox(height: 20),
                    Text(
                      _failed ? 'Need a bit more info' : 'Generating Your Itinerary',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kInk),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    if (_failed)
                      _FailedNotice(
                        message: context
                                .read<TravelProvider>()
                                .state
                                ?.reply ??
                            'The planner needs more details before it can build your trip.',
                      )
                    else ...[
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: Text(
                          _steps[_stepIndex],
                          key: ValueKey(_stepIndex),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, color: kMint),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 20),
                      AnimatedBuilder(
                        animation: _progress,
                        builder: (_, __) => Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: kMintLight,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: FractionallySizedBox(
                                widthFactor: _progress.value,
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: kMint,
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${(_progress.value * 100).toInt()}%',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: kMint),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Working with your collected preferences',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kSubtext),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const _SlotSummary(),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            const AppBottomNav(currentIndex: 0),
          ],
        ),
      ),
    );
  }
}

class _SlotSummary extends StatelessWidget {
  const _SlotSummary();

  @override
  Widget build(BuildContext context) {
    final slots = context.watch<TravelProvider>().state?.slots ?? const {};
    final entries = [
      ('Duration', slots['duration']),
      ('Region', slots['location']),
      ('Budget', slots['budget']),
      ('Dietary', slots['dietary']),
      ('Purpose', slots['purpose']),
    ].where((e) => (e.$2 ?? '').isNotEmpty).toList();

    return Column(
      children: [
        for (final e in entries)
          Opacity(
            opacity: 0.55,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kCardBorder),
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: kMintLight,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.check_rounded, color: kMint, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.$1,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, color: kSubtext)),
                        Text(e.$2!,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kInk)),
                      ]),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}

class _FailedNotice extends StatelessWidget {
  final String message;
  const _FailedNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to Chat'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kMint,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50)),
            ),
          ),
        ],
      ),
    );
  }
}
