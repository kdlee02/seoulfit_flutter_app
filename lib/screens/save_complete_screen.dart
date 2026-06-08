import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';

// 더미 JSON (FinalItineraryMapScreen과 동일한 구조)
const _dummyJson = {
  'title': 'Seoul 2-Day Itinerary',
  'score': 1.0,
  'duration': '2 Days',
  'budget': '\$300',
  'purpose': ['Cafe-hopping', 'K-POP'],
  'sources': ['Visit Seoul', 'Visit Korea', 'Kakao Local', 'Seoul OpenAPI'],
  'days': [
    {
      'day': 1,
      'theme': 'Hongdae Culture & Cafes',
      'places': [
        {'name': 'Cafe Bora', 'area': 'Hongdae', 'tag': 'Cafe', 'lat': 37.5546, 'lng': 126.9240},
        {'name': 'Vinyl & Plastic (HYBE)', 'area': 'Hongdae', 'tag': 'K-POP', 'lat': 37.5567, 'lng': 126.9234},
        {'name': 'Sangsang Madang', 'area': 'Hongdae', 'tag': 'K-POP', 'lat': 37.5551, 'lng': 126.9225},
      ],
    },
    {
      'day': 2,
      'theme': 'Seongsu & Heritage',
      'places': [
        {'name': 'Blue Bottle Coffee', 'area': 'Seongsu', 'tag': 'Cafe', 'lat': 37.5443, 'lng': 127.0557},
        {'name': 'Daelim Warehouse', 'area': 'Seongsu', 'tag': 'Art', 'lat': 37.5448, 'lng': 127.0563},
        {'name': 'Changdeokgung Palace', 'area': 'Jongno', 'tag': 'Heritage', 'lat': 37.5794, 'lng': 126.9910},
        {'name': 'Gyeongui Line Forest Park', 'area': 'Mapo', 'tag': 'Park', 'lat': 37.5593, 'lng': 126.9230},
      ],
    },
  ],
};

class SaveCompleteScreen extends StatefulWidget {
  const SaveCompleteScreen({super.key});

  @override
  State<SaveCompleteScreen> createState() => _SaveCompleteScreenState();
}

class _SaveCompleteScreenState extends State<SaveCompleteScreen> {
  String _jsonPreview = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadJsonPreview());
  }

  void _loadJsonPreview() {
    final args = ModalRoute.of(context)?.settings.arguments;
    final filePath = args is String ? args : null;

    if (filePath != null) {
      final file = File(filePath);
      if (file.existsSync()) {
        setState(() => _jsonPreview = file.readAsStringSync());
        return;
      }
    }
    // 파일 없으면 더미 데이터 표시
    const encoder = JsonEncoder.withIndent('  ');
    setState(() => _jsonPreview = encoder.convert(_dummyJson));
  }

  String get _fileName {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String) {
      return args.split('/').last;
    }
    return 'seoulfit_itinerary.json';
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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  children: [
                    // 성공 헤더
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            color: kSuccess,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 30, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Image.asset(
                          'assets/images/seoulfit_mascot.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Your itinerary has been saved!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: kInk,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 파일명 배지
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kCardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.insert_drive_file_rounded,
                              size: 15, color: kMint),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _fileName,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: kSubtext),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // JSON 미리보기 카드
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 320),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kCardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 카드 헤더
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                            decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(color: kCardBorder)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.code_rounded,
                                  size: 14, color: kMint),
                              const SizedBox(width: 6),
                              Text('JSON Preview',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: kInk)),
                            ]),
                          ),
                          // 스크롤 가능한 JSON 텍스트
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: _jsonPreview.isEmpty
                                  ? const Center(
                                      child: CircularProgressIndicator())
                                  : SelectableText(
                                      _jsonPreview,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: kInk,
                                        height: 1.6,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 버튼 행
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _shareItinerary(context, _fileName),
                          icon: const Icon(Icons.share_rounded,
                              size: 18, color: kMint),
                          label: Text('공유하기',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  color: kMint,
                                  fontSize: 15)),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(
                                color: kMint, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.pushNamedAndRemoveUntil(
                                  context, '/', (_) => false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kMint,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50)),
                            elevation: 0,
                          ),
                          child: Text('확인',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _shareItinerary(BuildContext context, String fileName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('공유 기능은 준비 중입니다.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
