import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_keys.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';

const _placesApiKey = ApiKeys.places;

class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({super.key});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  static const _dummyPlaces = [
    _PlaceData(
      name: 'Cafe Bora',
      category: 'Cafe',
      address: '서울 마포구 어울마당로 31',
      hours: '11:00 - 21:00 (Mon-Sun)',
      description:
          'Famous for its charcoal soft-serve and Instagram-worthy interiors. A must-visit cafe in Hongdae.',
      lat: 37.5546,
      lng: 126.9240,
    ),
    _PlaceData(
      name: 'Blue Bottle Coffee',
      category: 'Cafe',
      address: '서울 성동구 왕십리로2길 20',
      hours: '08:00 - 20:00 (Mon-Sun)',
      description:
          'Third-wave specialty coffee in the trendy Seongsu district. Known for single-origin pour-overs.',
      lat: 37.5443,
      lng: 127.0557,
    ),
    _PlaceData(
      name: 'Changdeokgung Palace',
      category: 'Heritage',
      address: '서울 종로구 율곡로 99',
      hours: '09:00 - 17:30 (Closed Mon)',
      description:
          'UNESCO World Heritage Site. Built in 1405, featuring the stunning Secret Garden (Huwon).',
      lat: 37.5794,
      lng: 126.9910,
    ),
  ];

  String? _photoUrl;
  bool _photoLoading = true;

  late _PlaceData _place;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    final placeName = args is String ? args : null;
    _place = placeName != null
        ? _dummyPlaces.firstWhere(
            (p) => p.name == placeName,
            orElse: () => _dummyPlaces.first,
          )
        : _dummyPlaces.first;
    _fetchPhoto(_place.name);
  }

  Future<void> _fetchPhoto(String placeName) async {
    setState(() => _photoLoading = true);
    try {
      // Step 1: Text Search to get photo_reference
      final searchUri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json'
        '?query=${Uri.encodeComponent(placeName + ' Seoul')}'
        '&key=$_placesApiKey',
      );
      final searchRes = await http.get(searchUri);
      if (searchRes.statusCode == 200) {
        final data = jsonDecode(searchRes.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          final photos = results.first['photos'] as List<dynamic>?;
          if (photos != null && photos.isNotEmpty) {
            final ref = photos.first['photo_reference'] as String?;
            if (ref != null) {
              setState(() {
                _photoUrl =
                    'https://maps.googleapis.com/maps/api/place/photo'
                    '?maxwidth=800&photo_reference=$ref&key=$_placesApiKey';
              });
            }
          }
        }
      }
    } catch (_) {
      // keep _photoUrl null — shows placeholder
    } finally {
      if (mounted) setState(() => _photoLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            // Header
            Container(
              color: kCard,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: kInk),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _place.name,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kInk),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kMintLight,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      _place.category,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kMint),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Photo with shimmer
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _photoLoading
                          ? Shimmer.fromColors(
                              baseColor: const Color(0xFFE0E0E0),
                              highlightColor: const Color(0xFFF5F5F5),
                              child: Container(
                                width: double.infinity,
                                height: 200,
                                color: Colors.white,
                              ),
                            )
                          : _photoUrl != null
                              ? Image.network(
                                  _photoUrl!,
                                  width: double.infinity,
                                  height: 200,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (_, child, progress) {
                                    if (progress == null) return child;
                                    return Shimmer.fromColors(
                                      baseColor: const Color(0xFFE0E0E0),
                                      highlightColor: const Color(0xFFF5F5F5),
                                      child: Container(
                                        width: double.infinity,
                                        height: 200,
                                        color: Colors.white,
                                      ),
                                    );
                                  },
                                  errorBuilder: (_, __, ___) =>
                                      _PhotoPlaceholder(name: _place.name),
                                )
                              : _PhotoPlaceholder(name: _place.name),
                    ),
                    const SizedBox(height: 20),
                    _InfoRow(
                        icon: Icons.location_on_rounded,
                        label: 'Address',
                        value: _place.address),
                    const SizedBox(height: 12),
                    _InfoRow(
                        icon: Icons.schedule_rounded,
                        label: 'Hours',
                        value: _place.hours),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kCardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('About',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: kInk)),
                          const SizedBox(height: 8),
                          Text(
                            _place.description,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: kSubtext,
                                height: 1.6),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _openInKakaoMap(_place),
                        icon: const Icon(Icons.map_rounded, size: 18),
                        label: Text(
                          '카카오맵에서 보기',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFE000),
                          foregroundColor: Colors.black,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50)),
                          elevation: 0,
                          textStyle: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInKakaoMap(_PlaceData place) async {
    final deepLink = Uri.parse(
        'kakaomap://look?p=${place.lat},${place.lng}');
    final webFallback = Uri.parse(
        'https://map.kakao.com/link/map/${Uri.encodeComponent(place.name)},${place.lat},${place.lng}');

    if (await canLaunchUrl(deepLink)) {
      await launchUrl(deepLink);
    } else {
      await launchUrl(webFallback, mode: LaunchMode.externalApplication);
    }
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  final String name;
  const _PhotoPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: kMintLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.place_rounded, size: 40, color: kMint),
          const SizedBox(height: 8),
          Text(name,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w600, color: kMint)),
        ],
      ),
    );
  }
}

class _PlaceData {
  final String name;
  final String category;
  final String address;
  final String hours;
  final String description;
  final double lat;
  final double lng;

  const _PlaceData({
    required this.name,
    required this.category,
    required this.address,
    required this.hours,
    required this.description,
    required this.lat,
    required this.lng,
  });
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: kMint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kSubtext)),
                const SizedBox(height: 3),
                Text(value,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kInk)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
