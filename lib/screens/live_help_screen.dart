import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/live_help.dart';
import '../services/live_help_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/mascot_widget.dart';

enum _View { hub, passport, emergency, nearby }

/// 여행 중 도우미. 여행 전 챗봇(/chat)과 달리 LLM 을 호출하지 않고
/// 퀵액션 3버튼으로만 동작한다 — 응급 상황에서 지연도 환각도 만들지 않기 위해서다.
class LiveHelpScreen extends StatefulWidget {
  const LiveHelpScreen({super.key});

  @override
  State<LiveHelpScreen> createState() => _LiveHelpScreenState();
}

class _LiveHelpScreenState extends State<LiveHelpScreen> {
  _View _view = _View.hub;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            _Header(
              showBack: _view != _View.hub,
              onBack: () => setState(() => _view = _View.hub),
            ),
            const Divider(height: 1),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  Widget _body() {
    switch (_view) {
      case _View.hub:
        return _Hub(onPick: (v) => setState(() => _view = v));
      case _View.passport:
        return const _PassportView();
      case _View.emergency:
      case _View.nearby:
        // Task 6 에서 채운다.
        return const SizedBox.shrink();
    }
  }
}

class _Header extends StatelessWidget {
  final bool showBack;
  final VoidCallback onBack;
  const _Header({required this.showBack, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kCard,
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.md),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              color: kInk,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            )
          else
            const MascotWidget(size: 38, variant: MascotVariant.chip),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SeoulFit Buddy 🐣',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
                Text('On-trip help',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: kSubtext)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hub extends StatelessWidget {
  final ValueChanged<_View> onPick;
  const _Hub({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Insets.lg),
      children: [
        Text('What can I help you with?',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
        const SizedBox(height: Insets.xs),
        Text("Tell me what happened and I'll pull it up right away.",
            style:
                GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext)),
        const SizedBox(height: Insets.xl),
        _ActionCard(
          icon: Icons.badge_outlined,
          title: 'Lost passport',
          subtitle: 'Find your embassy in Seoul',
          onTap: () => onPick(_View.passport),
        ),
        const SizedBox(height: Insets.md),
        _ActionCard(
          icon: Icons.local_hospital_outlined,
          title: 'Emergency room',
          subtitle: 'Nearest ER with live bed availability',
          danger: true,
          onTap: () => onPick(_View.emergency),
        ),
        const SizedBox(height: Insets.md),
        _ActionCard(
          icon: Icons.place_outlined,
          title: 'Near me',
          subtitle: 'Cafes and restaurants within walking distance',
          onTap: () => onPick(_View.nearby),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool danger;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = danger ? kDanger : kMint;
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(Insets.lg),
          decoration: BoxDecoration(
            border: Border.all(color: kCardBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: danger ? kDangerWash : kMintLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kInk)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: kSubtext)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kSubtext),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _launch(Uri uri) async {
  if (await canLaunchUrl(uri)) await launchUrl(uri);
}

/// 여권분실. 데이터가 앱에 번들되어 있어 네트워크 실패 경로가 없다.
class _PassportView extends StatefulWidget {
  const _PassportView();

  @override
  State<_PassportView> createState() => _PassportViewState();
}

class _PassportViewState extends State<_PassportView> {
  final _controller = TextEditingController();
  List<Embassy> _all = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    LiveHelpService.loadEmbassies().then((v) {
      if (mounted) setState(() => _all = v);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits = _all.where((e) => e.matches(_query)).toList();
    return Column(
      children: [
        const _EmergencyNumbersBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Insets.lg, Insets.md, Insets.lg, Insets.sm),
          child: TextField(
            controller: _controller,
            onChanged: (v) => setState(() => _query = v),
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: kInk),
            decoration: InputDecoration(
              hintText: 'Search your country — Philippines, 필리핀, PH',
              hintStyle:
                  GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext),
              prefixIcon: const Icon(Icons.search_rounded, color: kSubtext),
              filled: true,
              fillColor: kCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kCardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kCardBorder),
              ),
            ),
          ),
        ),
        Expanded(
          child: hits.isEmpty
              ? Center(
                  child: Text('No embassy found for "$_query"',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: kSubtext)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      Insets.lg, 0, Insets.lg, Insets.xl),
                  itemCount: hits.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: Insets.md),
                  itemBuilder: (_, i) => _EmbassyCard(hits[i]),
                ),
        ),
      ],
    );
  }
}

/// 여권 분실 시 실제로 통화가 되는 두 번호. 대사관 대표전화는 새벽에 받지
/// 않지만 이 둘은 24시간이다. 데이터에 긴급전화 필드가 아예 없어서 이 배너가
/// 그 구멍을 메운다.
class _EmergencyNumbersBanner extends StatelessWidget {
  const _EmergencyNumbersBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, 0),
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: kYellowLight,
        border: Border.all(color: kWarningBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report to the police first, then your embassy.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Expanded(
                child: _PhonePill(
                  label: '1330 · 24h interpreter',
                  number: '1330',
                ),
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: _PhonePill(label: '112 · Police', number: '112'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhonePill extends StatelessWidget {
  final String label;
  final String number;
  const _PhonePill({required this.label, required this.number});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _launch(Uri(scheme: 'tel', path: number)),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.sm),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.call_rounded, size: 14, color: kInk),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kInk)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmbassyCard extends StatelessWidget {
  final Embassy e;
  const _EmbassyCard(this.e);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.countryEn,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
          Text(e.countryKo,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: kSubtext)),
          const SizedBox(height: Insets.md),
          // 한글 주소를 그대로 노출한다 — 택시 기사에게 화면을 보여주는 용도다.
          Text(e.addressKo,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: kInk, height: 1.4)),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              if (e.phoneDial.isNotEmpty)
                _MiniButton(
                  icon: Icons.call_rounded,
                  label: e.phone,
                  onTap: () => _launch(
                      Uri(scheme: 'tel', path: e.phoneDial.replaceAll('-', ''))),
                ),
              _MiniButton(
                icon: Icons.map_outlined,
                label: 'Map',
                onTap: () => _launch(Uri.parse(
                    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(e.addressKo)}')),
              ),
              if (e.website.isNotEmpty)
                _MiniButton(
                  icon: Icons.language_rounded,
                  label: 'Website',
                  onTap: () => _launch(Uri.parse(e.website)),
                ),
              if (e.email.isNotEmpty)
                _MiniButton(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  onTap: () => _launch(Uri(scheme: 'mailto', path: e.email)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.sm),
        decoration: BoxDecoration(
          color: kMintLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: kMint),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: kInk)),
          ],
        ),
      ),
    );
  }
}
