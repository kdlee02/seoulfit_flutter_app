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
///
/// 세션 한정 메모리: Chat 탭에서 마지막으로 활성화됐던 하위 라우트
/// ('/chat' 또는 '/live-help'). AppBottomNav 의 index 0 이 하드코딩된
/// '/chat' 대신 이 값을 읽어서, 다른 탭에 갔다가 Chat 으로 돌아왔을 때
/// 사용자가 있던 모드(예: 응급실 목록을 보던 중)를 그대로 복원한다.
/// 앱 재시작 간에는 유지되지 않고, 상태관리 패키지나 영속화도 쓰지 않는다
/// — Navigator 백스택처럼 한 세션 동안만 살아있으면 되는 UI 메모리라서다.
String lastChatRoute = '/chat';

class ChatModeToggle extends StatelessWidget {
  /// 현재 화면이 On-trip 인지. true 면 오른쪽 세그먼트가 선택 상태다.
  final bool liveMode;

  const ChatModeToggle({super.key, required this.liveMode});

  void _go(BuildContext context, String route) {
    if (ModalRoute.of(context)?.settings.name == route) return;
    lastChatRoute = route;
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
            const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 5),
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
