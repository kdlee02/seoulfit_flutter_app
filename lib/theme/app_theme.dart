import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kMint = Color(0xFF4FD1C5);
const kMintLight = Color(0xFFB2EFE9);
const kYellow = Color(0xFFFDE047);
const kYellowLight = Color(0xFFFEF9C3);
const kCanvas = Color(0xFFF9F8F6);
const kInk = Color(0xFF1F2933);
const kSubtext = Color(0xFF7B8597);
const kCard = Color(0xFFFFFFFF);
const kCardBorder = Color(0xFFE8E6E1);
const kWarning = Color(0xFFFDE047);
const kWarningBorder = Color(0xFFF59E0B);
const kSuccess = Color(0xFF10B981);

/// 응급 UI 전용 위험색. 만원인 응급실, 119 배너처럼 "지금 문제가 있다"를
/// 나타내는 곳에만 쓴다. 일반 경고는 kWarning 을 계속 쓴다.
const kDanger = Color(0xFFE53E3E);
const kDangerWash = Color(0xFFFDECEC);

/// 여행 일차별 구분색. 일정 지도와 완주 기록 지도가 같은 날짜를 같은 색으로
/// 그려야 해서 여기 한 벌만 둔다. 목록보다 일수가 많으면 순환한다.
const kDayColors = [
  kMint,
  Color(0xFF457B9D), // sky blue
  Color(0xFFF59E0B), // amber
  Color(0xFF7C3AED), // violet
  Color(0xFFE63946), // persimmon
];

/// 관광 카테고리(한국관광공사 lclsSystm1) 구분색. 지도 마커·칩·순번 배지가
/// 같은 색을 써야 마커와 카드가 눈으로 이어진다.
///
/// 값은 [kDayColors] 와 겹치지만 의미 축이 다르므로(여행 일차 vs 카테고리)
/// 따로 둔다 — 한쪽 팔레트를 조정할 때 다른 쪽이 딸려가면 안 된다.
/// mint 는 일부러 뺐다. 같은 지도 위에서 "내 위치" 점이 mint 라서
/// 카테고리에 쓰면 내 위치와 POI 를 구분할 수 없다.
const kCategoryColors = <String, Color>{
  'VE': Color(0xFF7C3AED), // Culture — violet
  'EX': Color(0xFFF59E0B), // Experience — amber
  'HS': Color(0xFFE63946), // History — persimmon
  'NA': kSuccess, //          Nature — green
  'LS': Color(0xFFDB2777), // Leisure — magenta
  'AC': Color(0xFF457B9D), // Stay — sky blue
};

/// 쇼핑 카테고리(Visit Seoul 하위 분류) 구분색. [kCategoryColors] 와 코드가
/// 겹치지 않아 같은 맵에 합쳐도 되지만, 축이 다르므로 따로 둔다.
///
/// 여섯 색 모두 흰 글자 대비비 4.4 이상이라 마커 안 숫자가 읽힌다
/// (SP 4.47 / TM 3.56 / MO 3.68 / DS 6.29 / DF 5.38 / SW 4.99).
/// 관광 팔레트와 같은 이유로 mint 는 뺐다 — 지도의 "내 위치" 점 색이다.
const kShoppingColors = <String, Color>{
  'SP': Color(0xFF6366F1), // Shops — indigo
  'TM': Color(0xFFEA580C), // Traditional markets — terracotta
  'MO': Color(0xFF0891B2), // Malls & outlets — cyan
  'DS': Color(0xFFBE123C), // Department stores — rose
  'DF': Color(0xFF9333EA), // Duty free — purple
  'SW': Color(0xFF4D7C0F), // Supermarkets — olive
};

/// 칩·시트에 쓰는 짧은 이름. 백엔드 코드와 1:1 이다.
const kShoppingNames = <String, String>{
  'SP': 'Shops',
  'TM': 'Markets',
  'MO': 'Malls',
  'DS': 'Dept stores',
  'DF': 'Duty free',
  'SW': 'Supermarkets',
};

Color shoppingColor(String category) => kShoppingColors[category] ?? kSubtext;

/// 카테고리색 위에 얹는 글자색. amber·green 은 흰 글자 대비비가 2.15 / 2.54 라
/// 마커 안 숫자가 읽히지 않아 [kInk] 를 쓴다 (각각 6.87 / 5.82).
Color categoryFg(String category) =>
    category == 'EX' || category == 'NA' ? kInk : kCard;

Color categoryColor(String category) => kCategoryColors[category] ?? kSubtext;

/// Spacing scale (4pt grid). Use these instead of ad-hoc magic numbers so
/// rhythm stays consistent across screens.
class Insets {
  Insets._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Soft elevation tokens. The original theme rendered every card perfectly
/// flat; a micro-interaction UI benefits from a hint of depth that lifts cards
/// off the warm canvas without looking heavy.
class Elevations {
  Elevations._();

  /// Resting shadow for cards and tiles.
  static List<BoxShadow> get card => [
        BoxShadow(
          color: kInk.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  /// Stronger shadow for sheets, popovers, and the active/selected state.
  static List<BoxShadow> get lifted => [
        BoxShadow(
          color: kInk.withValues(alpha: 0.10),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ];

  /// Mint-tinted glow for the primary CTA, so the brand colour reads as the
  /// single bold accent on the page.
  static List<BoxShadow> get mintGlow => [
        BoxShadow(
          color: kMint.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kMint,
          surface: kCanvas,
        ),
        scaffoldBackgroundColor: kCanvas,
        textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
          displayLarge: GoogleFonts.plusJakartaSans(
            color: kInk,
            fontWeight: FontWeight.w800,
            fontSize: 28,
            letterSpacing: -0.5,
            height: 1.15,
          ),
          displayMedium: GoogleFonts.plusJakartaSans(
            color: kInk,
            fontWeight: FontWeight.w700,
            fontSize: 22,
            letterSpacing: -0.3,
            height: 1.2,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            color: kInk,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            color: kInk,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(
            color: kInk,
            fontWeight: FontWeight.w400,
            fontSize: 14,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            color: kSubtext,
            fontWeight: FontWeight.w400,
            fontSize: 13,
          ),
          labelSmall: GoogleFonts.plusJakartaSans(
            color: kSubtext,
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: kCanvas,
          elevation: 0,
          iconTheme: const IconThemeData(color: kInk),
          titleTextStyle: GoogleFonts.plusJakartaSans(
            color: kInk,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kMint,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: kCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: kCardBorder, width: 1),
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
        dividerTheme: const DividerThemeData(
          color: kCardBorder,
          thickness: 1,
        ),
      );
}