import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // 실제 로그인 연동 시 이 변수들을 교체
  final String _userName = 'jihyun';
  final int _userAge = 23;

  bool _notificationsEnabled = true;
  String _language = 'English';

  static const _trips = [
    _TripRecord('Hongdae · Seongsu', '2 Days', 'Cafe & K-POP', '2025.05.28'),
    _TripRecord('Gangnam · Itaewon', '1 Day', 'Shopping', '2025.05.15'),
    _TripRecord('Jongno · Insadong', '1 Day', 'Heritage', '2025.04.30'),
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
                    const SizedBox(height: 20),
                    _buildHeader(),
                    const SizedBox(height: 28),
                    _sectionLabel('My Trips'),
                    const SizedBox(height: 12),
                    ..._trips.map((t) => _TripCard(trip: t)),
                    const SizedBox(height: 28),
                    _sectionLabel('Settings'),
                    const SizedBox(height: 12),
                    _buildSettingsCard(),
                    const SizedBox(height: 24),
                    _buildLogoutButton(context),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            const AppBottomNav(currentIndex: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: kMint,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _userName[0].toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _userName,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: kInk,
                ),
              ),
              Text(
                'Age $_userAge',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: kSubtext),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kMintLight,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              'Edit',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kMint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: kSubtext,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        children: [
          _SettingsTile(
            icon: Icons.language_rounded,
            title: 'Language',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_language,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: kSubtext)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: kSubtext),
              ],
            ),
            onTap: () => _showLanguagePicker(),
          ),
          const Divider(height: 1, color: kCardBorder),
          _SettingsTile(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            trailing: Switch.adaptive(
              value: _notificationsEnabled,
              onChanged: (v) => setState(() => _notificationsEnabled = v),
              activeTrackColor: kMint,
            ),
          ),
          const Divider(height: 1, color: kCardBorder),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: 'App Version',
            trailing: Text('1.0.0',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: kSubtext)),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: kCardBorder,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          for (final lang in ['English', '한국어', '日本語', '中文'])
            ListTile(
              title: Text(lang,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: _language == lang
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: _language == lang ? kMint : kInk)),
              trailing: _language == lang
                  ? const Icon(Icons.check_rounded, color: kMint)
                  : null,
              onTap: () {
                setState(() => _language = lang);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirmLogout(context),
        icon: const Icon(Icons.logout_rounded,
            size: 18, color: Color(0xFFEF4444)),
        label: Text(
          'Log Out',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFEF4444)),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
          side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Log Out',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, color: kInk)),
        content: Text('정말 로그아웃 하시겠습니까?',
            style: GoogleFonts.plusJakartaSans(color: kSubtext)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소',
                  style: GoogleFonts.plusJakartaSans(color: kSubtext))),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamedAndRemoveUntil(
                    context, '/', (_) => false);
              },
              child: Text('로그아웃',
                  style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFEF4444),
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _TripRecord {
  final String areas;
  final String duration;
  final String theme;
  final String date;
  const _TripRecord(this.areas, this.duration, this.theme, this.date);
}

class _TripCard extends StatelessWidget {
  final _TripRecord trip;
  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kMintLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.map_rounded, color: kMint, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trip.areas,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
                const SizedBox(height: 3),
                Text('${trip.duration} · ${trip.theme}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: kSubtext)),
              ],
            ),
          ),
          Text(trip.date,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: kSubtext)),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: kMint),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kInk)),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
