import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../providers/travel_provider.dart';

class SlotParsingScreen extends StatefulWidget {
  const SlotParsingScreen({super.key});

  @override
  State<SlotParsingScreen> createState() => _SlotParsingScreenState();
}

class _SlotParsingScreenState extends State<SlotParsingScreen> {
  bool _isEditing = false;

  static const _slotMeta = [
    _SlotMeta(icon: Icons.calendar_today_rounded, label: 'Duration', field: 'duration', isMint: true),
    _SlotMeta(icon: Icons.location_on_rounded, label: 'Region', field: 'location', isMint: true),
    _SlotMeta(icon: Icons.attach_money_rounded, label: 'Budget', field: 'budget', isMint: false),
    _SlotMeta(icon: Icons.restaurant_rounded, label: 'Dietary', field: 'dietary', isMint: false),
    _SlotMeta(icon: Icons.star_rounded, label: 'Purpose', field: 'purpose', isMint: false),
  ];

  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final slots = context.read<TravelProvider>().state?.slots ?? const {};
    _controllers = [
      for (final meta in _slotMeta)
        TextEditingController(text: slots[meta.field] ?? ''),
    ];
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  String get _originalInput {
    final msgs = context.read<TravelProvider>().messages;
    for (final m in msgs) {
      if (m.isUser) return m.text;
    }
    return '';
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _isEditing ? kYellowLight : kMintLight,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isEditing
                                  ? Icons.edit_rounded
                                  : Icons.auto_awesome_rounded,
                              size: 13,
                              color: _isEditing ? const Color(0xFFD97706) : kMint,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isEditing ? 'Edit Mode' : 'AI Slot Parsing Complete',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _isEditing ? const Color(0xFFD97706) : kMint),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isEditing ? 'Edit\nInformation' : 'Collected\nInformation',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: kInk,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isEditing
                          ? 'Modify your travel preferences below'
                          : 'Parsed from your natural language input',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext),
                    ),
                    const SizedBox(height: 24),

                    _isEditing ? _buildEditFields() : _buildSlotGrid(),

                    const SizedBox(height: 20),

                    if (!_isEditing && _originalInput.isNotEmpty) ...[
                      Container(
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
                              const Icon(Icons.format_quote_rounded, size: 16, color: kSubtext),
                              const SizedBox(width: 6),
                              Text('Original Input',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: kSubtext)),
                            ]),
                            const SizedBox(height: 8),
                            Text(
                              '"$_originalInput"',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: kInk,
                                  fontStyle: FontStyle.italic,
                                  height: 1.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                    ] else
                      const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isEditing
                            ? () => setState(() => _isEditing = false)
                            : () => Navigator.pushNamed(context, '/generating'),
                        icon: Icon(
                          _isEditing
                              ? Icons.check_rounded
                              : Icons.rocket_launch_rounded,
                          size: 18,
                        ),
                        label: Text(_isEditing ? 'Save Changes' : 'Confirm & Generate'),
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
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _isEditing = !_isEditing),
                        child: Text(
                          _isEditing ? 'Cancel' : 'Edit preferences',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: kSubtext,
                              decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
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

  Widget _buildSlotGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.8,
      ),
      itemCount: _slotMeta.length,
      itemBuilder: (_, i) => _SlotCard(
        meta: _slotMeta[i],
        value: _controllers[i].text.isEmpty ? '—' : _controllers[i].text,
      ),
    );
  }

  Widget _buildEditFields() {
    return Column(
      children: List.generate(_slotMeta.length, (i) {
        final meta = _slotMeta[i];
        final iconColor = meta.isMint ? kMint : const Color(0xFFD97706);
        final borderColor = meta.isMint ? kMint : kYellow;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kCardBorder),
          ),
          child: TextField(
            controller: _controllers[i],
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w600, color: kInk),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(meta.icon, size: 18, color: iconColor),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 48),
              labelText: meta.label,
              labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: iconColor),
              floatingLabelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 11, fontWeight: FontWeight.w700, color: borderColor),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
            ),
          ),
        );
      }),
    );
  }
}

class _SlotMeta {
  final IconData icon;
  final String label;
  final String field;
  final bool isMint;
  const _SlotMeta({
    required this.icon,
    required this.label,
    required this.field,
    required this.isMint,
  });
}

class _SlotCard extends StatelessWidget {
  final _SlotMeta meta;
  final String value;
  const _SlotCard({required this.meta, required this.value});

  @override
  Widget build(BuildContext context) {
    final bg = meta.isMint ? kMintLight : kYellowLight;
    final border = meta.isMint ? kMint : kYellow;
    final iconColor = meta.isMint ? kMint : const Color(0xFFD97706);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(meta.icon, size: 14, color: iconColor),
            const SizedBox(width: 5),
            Text(
              meta.label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                  letterSpacing: 0.3),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: kInk,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
