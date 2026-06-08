import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';

class CriticRepairScreen extends StatelessWidget {
  const CriticRepairScreen({super.key});

  static const _pipelineNodes = [
    _PipelineNode('Draft', '✔', true),
    _PipelineNode('Critic', '🔍', true),
    _PipelineNode('Repair', '🛠', true),
    _PipelineNode('Final', '🏁', false),
  ];

  static const _repairLog = [
    _RepairEntry(
      icon: Icons.warning_amber_rounded,
      color: Color(0xFFD97706),
      text: 'Detected: Gyeongbokgung Palace closed on Tuesdays',
    ),
    _RepairEntry(
      icon: Icons.search_rounded,
      color: kMint,
      text: 'Searching alternatives near Gyeongbokgung...',
    ),
    _RepairEntry(
      icon: Icons.place_rounded,
      color: kMint,
      text: 'Alternative found: Changdeokgung Palace (0.8km away)',
    ),
    _RepairEntry(
      icon: Icons.route_rounded,
      color: kSuccess,
      text: 'Route adjusted · No constraint violations',
    ),
    _RepairEntry(
      icon: Icons.verified_rounded,
      color: kSuccess,
      text: 'Final itinerary validated · Overall score: 1.0',
    ),
  ];

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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: kMintLight,
                            borderRadius: BorderRadius.circular(50)),
                        child: Text('AI Verification',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: kMint)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Text('Critic-Repair\nLoop',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: kInk,
                            height: 1.2)),
                    const SizedBox(height: 4),
                    Text(
                        'Automated pipeline fixing schedule conflicts',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: kSubtext)),
                    const SizedBox(height: 24),
                    // Pipeline flow
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: kCardBorder),
                          boxShadow: [
                            BoxShadow(
                                color: kMint.withValues(alpha: 0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 6))
                          ]),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: List.generate(_pipelineNodes.length * 2 - 1, (i) {
                          if (i.isOdd) {
                            return const Icon(Icons.arrow_forward_ios_rounded,
                                size: 12, color: kSubtext);
                          }
                          return _PipelineNodeWidget(
                              node: _pipelineNodes[i ~/ 2]);
                        }),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Warning card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kYellowLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: kWarningBorder.withValues(alpha: 0.5),
                            width: 1.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: kYellow,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.warning_amber_rounded,
                                size: 20, color: Color(0xFF92400E)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Opening Hours Warning',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF92400E)),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Gyeongbokgung Palace is closed on Tuesdays!\nCritic agent detected scheduling conflict.',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: const Color(0xFF78350F),
                                      height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Repair Log',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: kInk)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kCardBorder)),
                      child: Column(
                        children: List.generate(
                          _repairLog.length,
                          (i) => _RepairLogRow(
                            entry: _repairLog[i],
                            isLast: i == _repairLog.length - 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/itinerary-map'),
                        icon:
                            const Icon(Icons.map_rounded, size: 18),
                        label: const Text('View Final Itinerary'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kMint,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50)),
                          elevation: 0,
                          textStyle: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                    ),
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

class _PipelineNode {
  final String label;
  final String emoji;
  final bool done;
  const _PipelineNode(this.label, this.emoji, this.done);
}

class _PipelineNodeWidget extends StatelessWidget {
  final _PipelineNode node;
  const _PipelineNodeWidget({required this.node});

  @override
  Widget build(BuildContext context) {
    final active = node.done;
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? kMint : kCanvas,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? kMint : kCardBorder,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(node.emoji,
                style: const TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 5),
        Text(node.label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: active ? kMint : kSubtext)),
      ],
    );
  }
}

class _RepairEntry {
  final IconData icon;
  final Color color;
  final String text;
  const _RepairEntry(
      {required this.icon, required this.color, required this.text});
}

class _RepairLogRow extends StatelessWidget {
  final _RepairEntry entry;
  final bool isLast;
  const _RepairLogRow({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: entry.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(entry.icon, size: 14, color: entry.color),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 18,
                color: kCardBorder,
                margin: const EdgeInsets.symmetric(vertical: 3),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 5, bottom: isLast ? 0 : 18),
            child: Text(
              entry.text,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: kInk, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
