import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import '../config/api_keys.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _Category {
  final String label;
  final String emoji;
  final List<String> keywords;

  const _Category({
    required this.label,
    required this.emoji,
    required this.keywords,
  });

  bool matches(String codename) {
    final lower = codename.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }
}

class _EventItem {
  final String title;
  final String date;
  final String place;
  final String category;
  final String imageUrl;

  const _EventItem({
    required this.title,
    required this.date,
    required this.place,
    required this.category,
    required this.imageUrl,
  });

  factory _EventItem.fromSeoulApi(Map<String, dynamic> json) {
    final start = (json['STRTDATE'] ?? '').toString().replaceAll('-', '.').split('T').first;
    final end   = (json['END_DATE']  ?? '').toString().replaceAll('-', '.').split('T').first;
    final date  = (start.isNotEmpty && end.isNotEmpty && start != end)
        ? '$start ~ $end'
        : start;

    return _EventItem(
      title:    (json['TITLE']     ?? '').toString().trim(),
      date:     date,
      place:    (json['PLACE']     ?? '').toString().trim(),
      category: (json['CODENAME']  ?? '').toString().trim(),
      imageUrl: (json['MAIN_IMG1'] ?? '').toString().trim(),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TransitExploreScreen extends StatefulWidget {
  const TransitExploreScreen({super.key});

  @override
  State<TransitExploreScreen> createState() => _TransitExploreScreenState();
}

class _TransitExploreScreenState extends State<TransitExploreScreen> {
  static const _categories = [
    _Category(label: 'Musical',    emoji: '🎭', keywords: ['뮤지컬', 'musical']),
    _Category(label: 'Concert',    emoji: '🎤', keywords: ['콘서트', 'concert']),
    _Category(label: 'Exhibition', emoji: '🖼',  keywords: ['전시', 'exhibition']),
    _Category(label: 'Classic',    emoji: '🎹', keywords: ['클래식', '무용', 'classic']),
    _Category(label: 'Family',     emoji: '👪',  keywords: ['아동', '가족', 'family']),
    _Category(label: 'Theater',    emoji: '🎬', keywords: ['연극', 'theater']),
  ];

  static const _dummyEvents = [
    _EventItem(
      title: 'TAKUYA KIMURA Live Tour 2026',
      date: '06.29',
      place: 'KSPO DOME',
      category: '콘서트',
      imageUrl: '',
    ),
    _EventItem(
      title: '2026 82MAJOR FAN-CONCERT',
      date: '06.15',
      place: 'Seoul Olympic Hall',
      category: '콘서트',
      imageUrl: '',
    ),
    _EventItem(
      title: 'Seoul International Garden Show',
      date: '06.01 ~ 06.30',
      place: 'Seoul Forest',
      category: '전시',
      imageUrl: '',
    ),
    _EventItem(
      title: 'DDP Summer Exhibition',
      date: '06.15 ~ 08.31',
      place: 'DDP',
      category: '전시',
      imageUrl: '',
    ),
    _EventItem(
      title: 'The Phantom of the Opera Seoul',
      date: '06.01 ~ 08.31',
      place: 'Charlotte Theater',
      category: '뮤지컬',
      imageUrl: '',
    ),
    _EventItem(
      title: 'Seoul Philharmonic Orchestra',
      date: '06.20',
      place: 'Seoul Arts Center',
      category: '클래식',
      imageUrl: '',
    ),
    _EventItem(
      title: 'Korean Folk Village Festival',
      date: '06.15 ~ 07.31',
      place: 'Korean Folk Village',
      category: '아동',
      imageUrl: '',
    ),
    _EventItem(
      title: 'Nanta Show',
      date: '매일',
      place: 'Nanta Theater',
      category: '연극',
      imageUrl: '',
    ),
  ];

  List<_EventItem> _allEvents = [];
  bool _loading = true;
  int _selectedCategory = 0;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() => _loading = true);
    try {
      final url =
          'http://openapi.seoul.go.kr:8088/${ApiKeys.culturalEvent}/json/culturalEventInfo/1/100/';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final rows = (body['culturalEventInfo']?['row'] as List?) ?? [];
        final events = rows
            .map((e) => _EventItem.fromSeoulApi(e as Map<String, dynamic>))
            .where((e) => e.title.isNotEmpty)
            .toList();

        if (events.isNotEmpty) {
          setState(() {
            _allEvents = events;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}

    setState(() {
      _allEvents = [..._dummyEvents];
      _loading = false;
    });
  }

  List<_EventItem> get _filteredEvents {
    final cat = _categories[_selectedCategory];
    return _allEvents.where((e) => cat.matches(e.category)).toList();
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Events in Seoul',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: kInk),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Discover performances, exhibitions and\nfestivals during your trip',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13, color: kSubtext),
                              ),
                            ],
                          ),
                        ),
                        if (!_loading)
                          IconButton(
                            onPressed: _fetchEvents,
                            icon: const Icon(Icons.refresh_rounded,
                                color: kSubtext, size: 20),
                            tooltip: 'Refresh',
                          ),
                      ],
                    ),
                  ),
                  // Category grid — 3 columns × 2 rows
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.4,
                      ),
                      itemCount: _categories.length,
                      itemBuilder: (_, i) => _CategoryChip(
                        category: _categories[i],
                        selected: i == _selectedCategory,
                        onTap: () => setState(() => _selectedCategory = i),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Event list
                  Expanded(
                    child: _loading ? _buildShimmer() : _buildEventList(),
                  ),
                ],
              ),
            ),
            const AppBottomNav(currentIndex: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildEventList() {
    final events = _filteredEvents;
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_rounded, size: 48, color: kSubtext),
            const SizedBox(height: 12),
            Text('No events for this category',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
            const SizedBox(height: 6),
            Text('Try another category or refresh.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: kSubtext)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchEvents,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kMint,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50)),
                elevation: 0,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _EventCard(event: events[i]),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: kCardBorder,
      highlightColor: kCanvas,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _CategoryChip extends StatelessWidget {
  final _Category category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? kMint : kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? kMint : kCardBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(category.emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 5),
            Text(
              category.label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : kInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final _EventItem event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
        boxShadow: [
          BoxShadow(
            color: kMint.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 16:9 image
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: event.imageUrl.isNotEmpty
                  ? Image.network(
                      event.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
                    )
                  : const _ImagePlaceholder(),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (event.date.isNotEmpty) ...[
                  Text(
                    event.date,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE53E3E),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: kInk,
                    height: 1.3,
                  ),
                ),
                if (event.category.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: kMintLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      event.category,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kMint,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kMintLight,
      child: const Center(
        child: Icon(Icons.event_rounded, size: 36, color: kMint),
      ),
    );
  }
}
