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