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
          ),
          displayMedium: GoogleFonts.plusJakartaSans(
            color: kInk,
            fontWeight: FontWeight.w700,
            fontSize: 22,
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