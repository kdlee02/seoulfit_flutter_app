import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/live_help.dart';
import '../services/kakao_links.dart';
import '../services/live_help_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/chat_mode_toggle.dart';
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
        return _LocationGate(builder: (at) => _EmergencyView(at));
      case _View.nearby:
        return _LocationGate(builder: (at) => _NearbyView(at));
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
                Text('On-trip help',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: kSubtext)),
              ],
            ),
          ),
          const ChatModeToggle(liveMode: true),
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

/// 앱 밖으로 나가는 모든 tap 의 공통 경로. 응급 화면은 어떤 경우에도 막다른
/// 길을 만들지 않는다 — 다이얼러가 없거나 launch 가 실패해도 사용자가 손으로
/// 옮겨 적을 수 있게 원본 값(전화번호/주소/URL)을 스낵바로 보여준다.
/// 출발지를 아는 경우에만 by/{mode} 경로를 만들고, 모르면 도착지 검색으로 떨어뜨린다.
/// 출발지 없이 by/ 스킴을 쓰면 카카오가 좌표 자리를 빈 값으로 읽어 경로가 깨진다.
Uri _routeTo(LatLng? from, LatLng to, String name, KakaoRouteMode mode) =>
    from == null
        ? kakaoSearch(name.trim().isEmpty ? '${to.latitude},${to.longitude}' : name)
        : kakaoRoute(from: from, to: to, toName: name, mode: mode);

Future<void> _launch(BuildContext context, Uri uri, String display) async {
  var ok = false;
  try {
    if (await canLaunchUrl(uri)) {
      ok = await launchUrl(uri);
    }
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(display)),
    );
  }
}

/// 여권분실. 데이터가 앱에 번들되어 있어 네트워크 실패 경로가 없다.
class _PassportView extends StatefulWidget {
  const _PassportView();

  @override
  State<_PassportView> createState() => _PassportViewState();
}

class _PassportViewState extends State<_PassportView> {
  final _controller = TextEditingController();
  // null while the bundled asset is still loading; distinguishes "loading"
  // from "loaded, zero matches" so the empty-state message doesn't flash
  // before the first frame the data actually arrives on.
  List<Embassy>? _all;
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
    final all = _all;
    final hits = all?.where((e) => e.matches(_query)).toList();
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
          child: hits == null
              ? const Center(
                  child: CircularProgressIndicator(color: kMint),
                )
              : hits.isEmpty
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
          const Row(
            children: [
              Expanded(
                child: _PhonePill(
                  label: '1330 · 24h interpreter',
                  number: '1330',
                ),
              ),
              SizedBox(width: Insets.sm),
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
      onTap: () => _launch(context, Uri(scheme: 'tel', path: number), number),
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
                      context,
                      Uri(scheme: 'tel', path: e.phoneDial.replaceAll('-', '')),
                      e.phone),
                ),
              _MiniButton(
                icon: Icons.map_outlined,
                label: 'Map',
                onTap: () =>
                    _launch(context, kakaoSearch(e.addressKo), e.addressKo),
              ),
              if (e.website.isNotEmpty)
                _MiniButton(
                  icon: Icons.language_rounded,
                  label: 'Website',
                  onTap: () => _launch(context, Uri.parse(e.website), e.website),
                ),
              if (e.email.isNotEmpty)
                _MiniButton(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  onTap: () => _launch(
                      context, Uri(scheme: 'mailto', path: e.email), e.email),
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

/// GPS 를 시도하고, 실패하면 지역 수동 선택을 띄운다.
/// 응급 화면이 막다른 길이 되지 않도록 항상 좌표를 확보하는 것이 목적이다.
class _LocationGate extends StatefulWidget {
  final Widget Function(LatLng at) builder;
  const _LocationGate({required this.builder});

  @override
  State<_LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<_LocationGate> {
  LatLng? _at;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    LiveHelpService.currentLatLng().then((v) {
      if (!mounted) return;
      setState(() {
        _at = v;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kMint));
    }
    final at = _at;
    if (at != null) return widget.builder(at);
    return _AreaPicker(onPick: (v) => setState(() => _at = v));
  }
}

class _AreaPicker extends StatelessWidget {
  final ValueChanged<LatLng> onPick;
  const _AreaPicker({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Insets.lg),
      children: [
        Text("Couldn't get your location",
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
        const SizedBox(height: Insets.xs),
        Text('Pick the area you are in and I will search from there.',
            style:
                GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext)),
        const SizedBox(height: Insets.lg),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final entry in kSeoulAreas.entries)
              InkWell(
                onTap: () => onPick(entry.value),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Insets.lg, vertical: Insets.md),
                  decoration: BoxDecoration(
                    color: kCard,
                    border: Border.all(color: kCardBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(entry.key,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kInk)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// E-Gen 이 통째로 죽었을 때 보여줄 최소 목록. 서울 권역 대형병원 5곳을
/// 지리적으로 흩어 골랐다 (성북·종로·서대문·서초·송파). 전화번호는 전부
/// 응급실 직통번호(dutyTel3)이고 좌표·주소는 getEgytBassInfoInqire 실응답에서
/// 가져왔다. 응급 화면은 어떤 경우에도 막다른 길이 되면 안 된다.
const _kErFallback = <EmergencyRoom>[
  EmergencyRoom(
      name: '연세대학교의과대학세브란스병원',
      address: '서울특별시 서대문구 연세로 50-1 (신촌동)',
      lat: 37.562117, lng: 126.940828, distanceKm: 0,
      erPhone: '02-2227-7777', beds: 0, bedsState: 'unknown', updatedAt: ''),
  EmergencyRoom(
      name: '서울대학교병원',
      address: '서울특별시 종로구 대학로 101 (연건동)',
      lat: 37.579666, lng: 126.998963, distanceKm: 0,
      erPhone: '02-2072-2475', beds: 0, bedsState: 'unknown', updatedAt: ''),
  EmergencyRoom(
      name: '고려대학교의과대학부속병원 (안암병원)',
      address: '서울특별시 성북구 고려대로 73 (안암동5가)',
      lat: 37.587156, lng: 127.026471, distanceKm: 0,
      erPhone: '02-920-5374', beds: 0, bedsState: 'unknown', updatedAt: ''),
  EmergencyRoom(
      name: '가톨릭대학교 서울성모병원',
      address: '서울특별시 서초구 반포대로 222 (반포동)',
      lat: 37.501801, lng: 127.004727, distanceKm: 0,
      erPhone: '02-2258-2370', beds: 0, bedsState: 'unknown', updatedAt: ''),
  EmergencyRoom(
      name: '서울아산병원',
      address: '서울특별시 송파구 올림픽로43길 88 (풍납동)',
      lat: 37.526564, lng: 127.108238, distanceKm: 0,
      erPhone: '02-3010-3333', beds: 0, bedsState: 'unknown', updatedAt: ''),
];

/// 응급실. API 가 죽어도 119 안내와 대형병원 5곳은 항상 보인다.
class _EmergencyView extends StatefulWidget {
  final LatLng at;
  const _EmergencyView(this.at);

  @override
  State<_EmergencyView> createState() => _EmergencyViewState();
}

class _EmergencyViewState extends State<_EmergencyView> {
  List<EmergencyRoom>? _rooms;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    LiveHelpService.fetchEmergencyRooms(widget.at).then((v) {
      // A successful-but-empty response (data.go.kr error envelope that
      // slipped past the server guard, a traveller outside Seoul, E-Gen
      // maintenance) is treated the same as a failure so the fallback list
      // renders instead of a blank area under the 119 banner.
      if (mounted) {
        setState(() {
          if (v.isEmpty) {
            _failed = true;
          } else {
            _rooms = v;
          }
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    return Column(
      children: [
        const _Call119Banner(),
        Expanded(
          child: _failed
              ? ListView(
                  padding: const EdgeInsets.all(Insets.lg),
                  children: [
                    Text(
                      "Live hospital data is unavailable. These major ERs are open 24 hours — call ahead before you go.",
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: kSubtext, height: 1.5),
                    ),
                    const SizedBox(height: Insets.lg),
                    for (final r in _kErFallback) ...[
                      _RoomCard(r),
                      const SizedBox(height: Insets.md),
                    ],
                  ],
                )
              : rooms == null
                  ? const Center(
                      child: CircularProgressIndicator(color: kMint))
                  : ListView.separated(
                      padding: const EdgeInsets.all(Insets.lg),
                      itemCount: rooms.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: Insets.md),
                      itemBuilder: (_, i) => _RoomCard(rooms[i], from: widget.at),
                    ),
        ),
      ],
    );
  }
}

class _Call119Banner extends StatelessWidget {
  const _Call119Banner();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _launch(context, Uri(scheme: 'tel', path: '119'), '119'),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, 0),
        padding: const EdgeInsets.all(Insets.lg),
        decoration: BoxDecoration(
          color: kDangerWash,
          border: Border.all(color: kDanger),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.emergency_rounded, color: kDanger),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Call 119',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kDanger)),
                  Text('Ambulance and interpreter, 24 hours',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: kInk)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// E-Gen 의 `hvidate` (`yyyyMMddHHmmss`, 예: `20260821182414`) 를 사람이 읽을
/// 수 있는 시각으로 바꾼다. 60초 캐시 + 요청 지연이 있으니 병상 수를 실시간처럼
/// 보여주지 않기 위한 최소 신선도 힌트다. 형식이 안 맞으면(폴백 목록은 항상
/// 빈 문자열) null 을 돌려주고 호출부가 렌더링을 건너뛴다.
String? _formatBedsUpdatedAt(String raw) {
  if (raw.length < 12) return null;
  final hh = raw.substring(8, 10);
  final mm = raw.substring(10, 12);
  return 'Updated $hh:$mm';
}

class _RoomCard extends StatelessWidget {
  final EmergencyRoom r;

  /// 길찾기 출발지. 폴백 목록은 사용자 위치를 모른 채 그려질 수 있어 null 을 허용하고,
  /// 그때는 도착지만 넘겨 카카오가 기기 현재 위치를 출발지로 쓰게 한다.
  final LatLng? from;

  const _RoomCard(this.r, {this.from});

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
          Row(
            children: [
              Expanded(
                child: Text(r.name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
              ),
              const SizedBox(width: Insets.sm),
              // hvec 는 정원 초과를 음수로 쓴다. 만원일 때 숫자를 보여주지 않는다.
              // 폴백 목록은 bedsState 가 unknown 이라 뱃지를 아예 숨긴다.
              if (r.bedsState != 'unknown')
                _Pill(
                  text: r.isFull ? 'Full' : '${r.beds} beds',
                  fg: r.isFull ? kDanger : kSuccess,
                  bg: r.isFull ? kDangerWash : kMintLight,
                ),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Text(
              r.distanceKm > 0
                  ? '${r.distanceKm.toStringAsFixed(1)} km · ${r.address}'
                  : r.address,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: kSubtext, height: 1.4)),
          if (_formatBedsUpdatedAt(r.updatedAt) case final hint?) ...[
            const SizedBox(height: Insets.xs),
            Text(hint,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: kSubtext)),
          ],
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              if (r.erPhone.isNotEmpty)
                _MiniButton(
                  icon: Icons.call_rounded,
                  label: r.erPhone,
                  onTap: () => _launch(
                      context,
                      Uri(scheme: 'tel', path: r.erPhone.replaceAll('-', '')),
                      r.erPhone),
                ),
              _MiniButton(
                icon: Icons.directions_rounded,
                label: 'Directions',
                onTap: () => _launch(
                    context,
                    _routeTo(from, LatLng(r.lat, r.lng), r.name,
                        KakaoRouteMode.car),
                    r.address),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const _Pill({required this.text, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.xs),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

/// 주변 추천. 카페/음식점 토글 + 거리순 5개.
class _NearbyView extends StatefulWidget {
  final LatLng at;
  const _NearbyView(this.at);

  @override
  State<_NearbyView> createState() => _NearbyViewState();
}

class _NearbyViewState extends State<_NearbyView> {
  String _type = 'cafe';
  List<NearbyPlace>? _places;
  bool _failed = false;

  // Bumped on every _load() call and captured per-request. A response for a
  // stale generation (e.g. the "cafe" request resolving after a later
  // "restaurant" tap) is discarded instead of overwriting fresher results.
  int _gen = 0;

  final _scrollCtrl = ScrollController();

  /// 마커 탭 → 해당 카드로 스크롤하기 위한 카드별 키. 매 로드마다 갈아끼운다.
  List<GlobalKey> _cardKeys = const [];

  @override
  void initState() {
    super.initState();
    _load(_type);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _revealCard(int i) {
    if (i >= _cardKeys.length) return;
    final ctx = _cardKeys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.1);
  }

  void _load(String type) {
    final gen = ++_gen;
    setState(() {
      _type = type;
      _places = null;
      _failed = false;
    });
    LiveHelpService.fetchNearby(widget.at, type).then((v) {
      if (mounted && gen == _gen) {
        setState(() {
          _places = v;
          _cardKeys = List.generate(v.length, (_) => GlobalKey());
        });
      }
    }).catchError((_) {
      if (mounted && gen == _gen) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final places = _places;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Row(
            children: [
              for (final t in const ['cafe', 'restaurant'])
                Padding(
                  padding: const EdgeInsets.only(right: Insets.sm),
                  child: InkWell(
                    onTap: () {
                      if (_type == t) return;
                      _load(t);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Insets.lg, vertical: Insets.sm),
                      decoration: BoxDecoration(
                        color: _type == t ? kMintLight : kCard,
                        border: Border.all(
                            color: _type == t ? kMint : kCardBorder),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(t == 'cafe' ? 'Cafes' : 'Restaurants',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _type == t ? kMint : kSubtext)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (places != null && places.isNotEmpty)
          _NearbyMap(
            me: widget.at,
            places: places,
            onMarkerTap: _revealCard,
          ),
        Expanded(
          child: _failed
              ? Center(
                  child: Text("Couldn't load nearby places right now.",
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: kSubtext)),
                )
              : places == null
                  ? const Center(
                      child: CircularProgressIndicator(color: kMint))
                  : places.isEmpty
                      ? Center(
                          child: Text('Nothing within walking distance here.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13, color: kSubtext)),
                        )
                      : ListView.separated(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(
                              Insets.lg, Insets.md, Insets.lg, Insets.xl),
                          itemCount: places.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: Insets.md),
                          itemBuilder: (_, i) => _PlaceCard(
                            places[i],
                            key: i < _cardKeys.length ? _cardKeys[i] : null,
                            index: i + 1,
                            from: widget.at,
                          ),
                        ),
        ),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final NearbyPlace p;
  final LatLng? from;

  /// 지도 마커와 대응시키는 1-기반 순번.
  final int index;

  const _PlaceCard(this.p, {super.key, required this.index, this.from});

  @override
  Widget build(BuildContext context) {
    final openNow = p.openNow;
    final rating = p.rating;
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
          Row(
            children: [
              // 지도 마커와 같은 번호. 둘을 눈으로 잇는 유일한 단서라 항상 보인다.
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: Insets.sm),
                decoration: const BoxDecoration(
                    color: kInk, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('$index',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kCard)),
              ),
              Expanded(
                child: Text(p.name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
              ),
              // 리뷰가 없는 업소는 구글이 평점을 주지 않는다 — 그럴 땐 뱃지를 숨긴다.
              if (rating != null)
                _Pill(
                    text: '$rating★ (${p.reviews})',
                    fg: kInk,
                    bg: kYellowLight),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Text('${p.distanceM} m · ${p.address}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: kSubtext, height: 1.4)),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              if (openNow != null)
                _Pill(
                  text: openNow ? 'Open now' : 'Closed',
                  fg: openNow ? kSuccess : kSubtext,
                  bg: openNow ? kMintLight : kCanvas,
                ),
              _MiniButton(
                icon: Icons.directions_walk_rounded,
                label: 'Directions',
                onTap: () => _launch(
                    context,
                    _routeTo(from, LatLng(p.lat, p.lng), p.name,
                        KakaoRouteMode.walk),
                    p.address),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// 주변 추천 상단의 작은 지도.
///
/// kakao_map_plugin 이 아니라 flutter_map(OSM)을 쓴다 — 카카오 플러그인은
/// ios/android 전용이라 브라우저 개발 루프가 깨지고, 이 화면은 타일만 있으면
/// 되지 카카오 SDK 기능이 필요하지 않다. 길찾기는 카카오로 넘긴다.
class _NearbyMap extends StatelessWidget {
  final LatLng me;
  final List<NearbyPlace> places;
  final ValueChanged<int> onMarkerTap;

  const _NearbyMap({
    required this.me,
    required this.places,
    required this.onMarkerTap,
  });

  /// 내 위치와 결과가 모두 들어오도록 잡은 경계. 결과가 반경 1000m 안이라
  /// 여유값은 작게 둔다.
  LatLngBounds get _bounds {
    var minLat = me.latitude, maxLat = me.latitude;
    var minLng = me.longitude, maxLng = me.longitude;
    for (final p in places) {
      minLat = p.lat < minLat ? p.lat : minLat;
      maxLat = p.lat > maxLat ? p.lat : maxLat;
      minLng = p.lng < minLng ? p.lng : minLng;
      maxLng = p.lng > maxLng ? p.lng : maxLng;
    }
    const pad = 0.0012;
    return LatLngBounds(
      LatLng(minLat - pad, minLng - pad),
      LatLng(maxLat + pad, maxLng + pad),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit:
              CameraFit.bounds(bounds: _bounds, padding: const EdgeInsets.all(28)),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.seoulfitFlutter',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: me,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: kMint,
                    shape: BoxShape.circle,
                    border: Border.all(color: kCard, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: kInk.withValues(alpha: 0.25),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              for (var i = 0; i < places.length; i++)
                Marker(
                  point: LatLng(places[i].lat, places[i].lng),
                  width: 30,
                  height: 30,
                  child: GestureDetector(
                    onTap: () => onMarkerTap(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: kInk,
                        shape: BoxShape.circle,
                        border: Border.all(color: kCard, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text('${i + 1}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: kCard)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
