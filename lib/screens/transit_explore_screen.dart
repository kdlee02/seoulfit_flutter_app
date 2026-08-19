import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_base.dart';
import '../widgets/animations.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../providers/travel_provider.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _Category {
  final String label;
  final String emoji;
  const _Category({required this.label, required this.emoji});
}

class _BackendEvent {
  final String name;
  final String date;
  final String venue;
  final String description;
  final String imageUrl;
  final String landingUrl;

  const _BackendEvent({
    required this.name,
    required this.date,
    required this.venue,
    required this.description,
    required this.imageUrl,
    required this.landingUrl,
  });

  factory _BackendEvent.fromJson(Map<String, dynamic> json) => _BackendEvent(
        name: (json['name'] as String?) ?? '',
        date: (json['date'] as String?) ?? '',
        venue: (json['venue'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        imageUrl: (json['image_url'] as String?) ?? '',
        landingUrl: (json['landing_url'] as String?) ?? '',
      );
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
    _Category(label: 'Musical',    emoji: '🎭'),
    _Category(label: 'Concert',    emoji: '🎤'),
    _Category(label: 'Sports',     emoji: '🏟'),
    _Category(label: 'Exhibition', emoji: '🖼'),
    _Category(label: 'Classic',    emoji: '🎹'),
    _Category(label: 'Family',     emoji: '👪'),
    _Category(label: 'Theater',    emoji: '🎬'),
  ];

  int _selectedCategory = 0;
  List<_BackendEvent> _events = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() => _loading = true);
    final travelDates =
        context.read<TravelProvider>().state?.travelDates ?? '';
    final category = _categories[_selectedCategory].label;
    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/events'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'category': category, 'travel_dates': travelDates}),
          )
          .timeout(const Duration(seconds: 40));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        if (mounted) {
          setState(() {
            _events = list
                .map((e) =>
                    _BackendEvent.fromJson(e as Map<String, dynamic>))
                .toList();
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _events = [];
        _loading = false;
      });
    }
  }

  void _selectCategory(int i) {
    if (i == _selectedCategory) return;
    setState(() => _selectedCategory = i);
    _fetchEvents();
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
                  // Category strip — horizontal scrollable chips (7 items)
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 8),
                      itemBuilder: (_, i) => _CategoryChip(
                        category: _categories[i],
                        selected: i == _selectedCategory,
                        onTap: () => _selectCategory(i),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Event list
                  Expanded(
                    child: _loading ? _buildShimmer() : _buildEventGrid(),
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

  Widget _buildEventGrid() {
    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_rounded, size: 48, color: kSubtext),
            const SizedBox(height: 12),
            Text(
              'No events available during your trip',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kInk),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another category or refresh.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: kSubtext),
            ),
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

    return GridView.count(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.52,
      children: stagger(
        _events
            .map((e) => _EventPosterCard(
                  event: e,
                  onTap: () => _openEvent(e),
                ))
            .toList(),
      ),
    );
  }

  Future<void> _openEvent(_BackendEvent event) async {
    final url = event.landingUrl;
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: kCardBorder,
      highlightColor: kCanvas,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.52,
        ),
        itemCount: 4,
        itemBuilder: (_, __) => Container(
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
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? kMint : kCard,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: selected ? kMint : kCardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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

class _EventPosterCard extends StatelessWidget {
  final _BackendEvent event;
  final VoidCallback? onTap;
  const _EventPosterCard({required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
        boxShadow: [
          BoxShadow(
            color: kMint.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster image — 3:4 ratio
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: event.imageUrl.isNotEmpty
                  ? Image.network(
                      event.imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      // Cap decode resolution to the displayed size. Without
                      // this, full-res yanolja posters (1000+px) decode at full
                      // size and OOM-crash the app on real devices (the grid
                      // holds ~20 at once). Simulator survives on host RAM.
                      cacheWidth: 540,
                      errorBuilder: (_, __, ___) =>
                          const _PosterPlaceholder(),
                    )
                  : const _PosterPlaceholder(),
            ),
          ),
          // Text area
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event.date.isNotEmpty)
                    Text(
                      event.date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE53E3E),
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    event.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                      height: 1.3,
                    ),
                  ),
                  const Spacer(),
                  if (event.venue.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            size: 10, color: kSubtext),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            event.venue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 10, color: kSubtext),
                          ),
                        ),
                      ],
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
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

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
