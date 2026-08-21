import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Chat 탭의 두 모드를 오가는 세그먼트 토글.
///
/// 하단 탭 5개가 이미 만석이라 6번째를 넣는 대신 Chat 탭을 둘로 나눴다.
/// 두 화면 모두 AppBottomNav(currentIndex: 0) 을 쓰므로 pushReplacementNamed
/// 로 바꿔치기해도 탭 상태가 흔들리지 않는다.
///
/// 저장된 여행의 date 가 문자열이라 "여행 중"을 자동 판정할 수 없다.
/// 기본값은 Plan 이고 전환은 수동이다.
class ChatModeToggle extends StatelessWidget {
  /// 현재 화면이 On-trip 인지. true 면 오른쪽 세그먼트가 선택 상태다.
  final bool liveMode;

  const ChatModeToggle({super.key, required this.liveMode});

  void _go(BuildContext context, String route) {
    if (ModalRoute.of(context)?.settings.name == route) return;
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kCanvas,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(context, 'Plan', !liveMode, '/chat'),
          _seg(context, 'On-trip', liveMode, '/live-help'),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, bool on, String route) {
    return InkWell(
      onTap: () => _go(context, route),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 5),
        decoration: BoxDecoration(
          color: on ? kMint : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : kSubtext)),
      ),
    );
  }
}
