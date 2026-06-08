import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import '../models/travel_state.dart';

/// OSM-backed map: one polyline per day (color-coded), numbered circular
/// markers in visit order, tap to see the POI's name / type / stay time /
/// address.
class ItineraryMap extends StatefulWidget {
  final Itinerary itinerary;
  final double height;

  const ItineraryMap({super.key, required this.itinerary, this.height = 280});

  @override
  State<ItineraryMap> createState() => _ItineraryMapState();
}

class _ItineraryMapState extends State<ItineraryMap> {
  final MapController _mapController = MapController();

  /// Distinct colors per day, drawn from the SeoulFit palette.
  static const List<Color> _dayColors = [
    kMint,
    Color(0xFF457B9D), // sky blue
    Color(0xFFF59E0B), // amber
    Color(0xFF7C3AED), // violet
    Color(0xFFE63946), // persimmon
  ];

  Color _colorFor(int dayIndex) => _dayColors[dayIndex % _dayColors.length];

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final target = (camera.zoom + delta)
        .clamp(camera.minZoom ?? 1.0, camera.maxZoom ?? 19.0)
        .toDouble();
    _mapController.move(camera.center, target);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itinerary = widget.itinerary;
    final height = widget.height;
    final dayPoints = <List<_MapPoi>>[];
    for (final day in itinerary.days) {
      final pts = <_MapPoi>[];
      var seq = 1;
      for (final p in day.pois) {
        final lat = p.lat;
        final lng = p.lng;
        if (lat == null || lng == null) continue;
        pts.add(_MapPoi(
          poi: p,
          point: LatLng(lat, lng),
          sequence: seq++,
          day: day.day,
        ));
      }
      dayPoints.add(pts);
    }

    final allPoints = [for (final d in dayPoints) ...d];

    // De-overlap: stops at (nearly) the same coordinate would stack and hide
    // each other, so fan duplicates out on a tiny circle (~12 m). The polyline
    // still uses the true points; only the marker display position shifts.
    final displayPoint = <_MapPoi, LatLng>{};
    final seen = <String, int>{};
    for (final p in allPoints) {
      final key =
          '${p.point.latitude.toStringAsFixed(5)},${p.point.longitude.toStringAsFixed(5)}';
      final n = seen[key] ?? 0;
      seen[key] = n + 1;
      if (n == 0) {
        displayPoint[p] = p.point;
      } else {
        final angle = (n - 1) * (math.pi / 3); // 60° steps
        const r = 0.00012;
        displayPoint[p] = LatLng(
          p.point.latitude + r * math.sin(angle),
          p.point.longitude + r * math.cos(angle),
        );
      }
    }

    if (allPoints.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: kMintLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kCardBorder),
        ),
        child: const Center(
          child: Text(
            'No map coordinates available',
            style: TextStyle(color: kSubtext, fontSize: 13),
          ),
        ),
      );
    }

    final mapOptions = _buildMapOptions(allPoints);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: mapOptions,
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.seoulfit.app',
                  maxZoom: 19,
                ),
                PolylineLayer(
                  polylines: [
                    for (var i = 0; i < dayPoints.length; i++)
                      if (dayPoints[i].length >= 2)
                        Polyline(
                          points: [for (final p in dayPoints[i]) p.point],
                          strokeWidth: 3.5,
                          color: _colorFor(i),
                        ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < dayPoints.length; i++)
                      for (final p in dayPoints[i])
                        Marker(
                          width: 34,
                          height: 34,
                          point: displayPoint[p] ?? p.point,
                          alignment: Alignment.center,
                          child: _NumberedMarker(
                            number: p.sequence,
                            color: _colorFor(i),
                            onTap: () => _showPoi(context, p),
                          ),
                        ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Column(
                children: [
                  _ZoomButton(
                    icon: Icons.add,
                    onTap: () => _zoomBy(1),
                  ),
                  const SizedBox(height: 8),
                  _ZoomButton(
                    icon: Icons.remove,
                    onTap: () => _zoomBy(-1),
                  ),
                ],
              ),
            ),
            if (itinerary.days.length > 1)
              Positioned(
                left: 8,
                bottom: 8,
                child: _DayLegend(
                  days: [
                    for (var i = 0; i < dayPoints.length; i++)
                      if (dayPoints[i].isNotEmpty)
                        (
                          label: 'Day ${itinerary.days[i].day}',
                          color: _colorFor(i)
                        ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Enable the full set of map gestures (pinch / double-tap / scroll-wheel
  // zoom, drag) so the map stays interactive even nested in a scroll view.
  static const _interaction =
      InteractionOptions(flags: InteractiveFlag.all);

  MapOptions _buildMapOptions(List<_MapPoi> allPoints) {
    if (allPoints.length == 1) {
      return MapOptions(
        initialCenter: allPoints.first.point,
        initialZoom: 14,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: _interaction,
      );
    }
    final lats = allPoints.map((p) => p.point.latitude);
    final lngs = allPoints.map((p) => p.point.longitude);
    final bounds = LatLngBounds(
      LatLng(lats.reduce((a, b) => a < b ? a : b),
          lngs.reduce((a, b) => a < b ? a : b)),
      LatLng(lats.reduce((a, b) => a > b ? a : b),
          lngs.reduce((a, b) => a > b ? a : b)),
    );
    return MapOptions(
      minZoom: 3,
      maxZoom: 18,
      interactionOptions: _interaction,
      initialCameraFit: CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(40),
      ),
    );
  }

  void _showPoi(BuildContext context, _MapPoi p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PoiSheet(mapPoi: p),
    );
  }
}

class _MapPoi {
  final Poi poi;
  final LatLng point;
  final int sequence;
  final int day;

  _MapPoi({
    required this.poi,
    required this.point,
    required this.sequence,
    required this.day,
  });
}

class _NumberedMarker extends StatelessWidget {
  final int number;
  final Color color;
  final VoidCallback onTap;

  const _NumberedMarker({
    required this.number,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: kInk),
        ),
      ),
    );
  }
}

class _DayLegend extends StatelessWidget {
  final List<({String label, Color color})> days;

  const _DayLegend({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: days[i].color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              days[i].label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kInk,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PoiSheet extends StatelessWidget {
  final _MapPoi mapPoi;

  const _PoiSheet({required this.mapPoi});

  @override
  Widget build(BuildContext context) {
    final p = mapPoi.poi;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: kInk.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Day ${mapPoi.day} · Stop ${mapPoi.sequence}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kMint,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kInk,
            ),
          ),
          const SizedBox(height: 10),
          if (p.type.isNotEmpty)
            _SheetRow(icon: Icons.local_offer_outlined, text: p.type),
          if (p.stayMinutes > 0)
            _SheetRow(icon: Icons.schedule, text: '${p.stayMinutes} min stay'),
          if (p.address.isNotEmpty)
            _SheetRow(icon: Icons.location_on_outlined, text: p.address),
          if (p.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              p.notes,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: kInk.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SheetRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: kInk.withValues(alpha: 0.55)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: kInk.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
