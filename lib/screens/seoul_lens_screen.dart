import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../services/lens_service.dart';
import '../models/landmark_analysis.dart';

class SeoulLensScreen extends StatefulWidget {
  const SeoulLensScreen({super.key});

  @override
  State<SeoulLensScreen> createState() => _SeoulLensScreenState();
}

class _SeoulLensScreenState extends State<SeoulLensScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _scanCtrl;
  bool _sheetExpanded = true;
  final _picker = ImagePicker();
  final _lens = LensService();
  XFile? _pickedImage;
  Uint8List? _pickedBytes;
  bool _isAnalyzing = false;
  LandmarkAnalysis? _placeResult;
  String? _analyzeError;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showMediaPicker());
  }

  Future<void> _showMediaPicker() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: kCardBorder,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text('Seoul Lens',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
              const SizedBox(height: 4),
              Text('Choose a photo source',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: kSubtext)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: _SourceButton(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.camera) {
      // 카메라는 명시적 권한 요청 필요
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('카메라 권한이 필요합니다.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13)),
              action: const SnackBarAction(label: '설정', onPressed: openAppSettings),
            ),
          );
        }
        return;
      }
    }
    // 갤러리는 Android 시스템 포토피커가 권한을 자체 처리
    try {
      final file =
          await _picker.pickImage(source: source, imageQuality: 85);
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        setState(() {
          _pickedImage = file;
          _pickedBytes = bytes;
          _placeResult = null;
          _analyzeError = null;
          _sheetExpanded = true;
        });
        await _analyzeWithBackend(file, bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('이미지를 불러올 수 없습니다.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13)),
          ),
        );
      }
    }
  }

  Future<void> _analyzeWithBackend(XFile imageFile, Uint8List bytes) async {
    setState(() {
      _isAnalyzing = true;
      _analyzeError = null;
    });

    try {
      final result = await _lens.analyze(
        bytes,
        imageFile.name.isNotEmpty ? imageFile.name : 'capture.jpg',
      );
      if (mounted) {
        if (result.confidence == 0 &&
            result.nameEnglish.toLowerCase() == 'unknown') {
          setState(() => _analyzeError =
              "Couldn't recognize this place.\nTry another photo.");
        } else {
          setState(() => _placeResult = result);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _analyzeError =
            "Couldn't reach the analysis service.\nIs the backend running on :8000?");
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Widget _buildGeminiResult() {
    if (_isAnalyzing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kMint),
            SizedBox(height: 14),
            Text('Analyzing landmark...'),
          ],
        ),
      );
    }
    if (_analyzeError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(_analyzeError!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showMediaPicker,
                icon: const Icon(Icons.camera_alt_rounded, size: 16),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMint,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_placeResult != null) {
      final r = _placeResult!;
      // Prefer the English-translated value, fall back to the Korean original.
      String field(String key) {
        final en = (r.publicInfoEn[key] ?? '').trim();
        if (en.isNotEmpty) return en;
        return (r.publicInfo[key] ?? '').trim();
      }

      final address = field('address');
      final hours = field('hours');
      final openDays = field('open_days');
      final closedDays = field('closed_days');
      final subway = field('subway');
      final phone = field('phone');
      final website = field('website');
      final tags = field('tags');
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.nameEnglish,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
                  if (r.nameKorean.isNotEmpty)
                    Text(r.nameKorean,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: kSubtext)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: r.dataVerified ? kMintLight : kYellowLight,
                    borderRadius: BorderRadius.circular(50)),
                child: Row(children: [
                  Icon(
                      r.dataVerified
                          ? Icons.verified_rounded
                          : Icons.auto_awesome_rounded,
                      size: 12,
                      color: r.dataVerified ? kMint : const Color(0xFFD97706)),
                  const SizedBox(width: 4),
                  Text(r.dataVerified ? 'Verified' : 'AI Guess',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: r.dataVerified ? kMint : const Color(0xFFD97706))),
                ]),
              ),
            ]),
            Builder(builder: (_) {
              final rows = <Widget>[];
              void add(IconData icon, String label, String value,
                  {VoidCallback? onTap}) {
                if (value.isEmpty) return;
                if (rows.isNotEmpty) {
                  rows.add(const Divider(height: 1, color: kCardBorder));
                }
                rows.add(_DetailRow(
                    icon: icon, label: label, value: value, onTap: onTap));
              }

              add(Icons.access_time_rounded, 'HOURS', hours);
              add(Icons.event_available_rounded, 'OPEN', openDays);
              add(Icons.event_busy_rounded, 'CLOSED', closedDays);
              add(Icons.directions_subway_rounded, 'GETTING THERE', subway);
              add(Icons.location_on_rounded, 'ADDRESS', address);
              add(Icons.phone_rounded, 'PHONE', phone,
                  onTap: () =>
                      _launch('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}'));
              add(Icons.language_rounded, 'WEBSITE', website,
                  onTap: () => _launch(website));

              if (rows.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kCardBorder),
                ),
                child: Column(children: rows),
              );
            }),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tags
                    .split(',')
                    .map((t) => t.trim())
                    .where((t) => t.isNotEmpty)
                    .map((t) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                              color: kMintLight,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('#$t',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: kMint)),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kCanvas,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kCardBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI Audio Guide · ${r.category}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w700, color: kMint)),
                const SizedBox(height: 8),
                Text(r.description,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: kInk, height: 1.55)),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showMediaPicker,
                icon: const Icon(Icons.camera_alt_rounded, size: 16, color: kMint),
                label: Text('Scan Another Place',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, color: kMint, fontSize: 14)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: kMint, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const Center(child: CircularProgressIndicator(color: kMint));
  }

  Future<void> _launch(String url) async {
    var u = url.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('tel:') &&
        !u.startsWith('http://') &&
        !u.startsWith('https://')) {
      u = 'https://$u';
    }
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $url',
              style: GoogleFonts.plusJakartaSans(fontSize: 13)),
        ),
      );
    }
  }

  Widget _buildEmptyPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: kMintLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.center_focus_strong_rounded,
                  size: 30, color: kMint),
            ),
            const SizedBox(height: 16),
            Text('Point at a Seoul landmark',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
            const SizedBox(height: 6),
            Text(
              'Take a photo or pick one from your gallery, and Seoul Lens '
              'will identify it with opening hours and more.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: kSubtext, height: 1.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showMediaPicker,
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('Scan a Place'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kMint,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50)),
                textStyle: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final sheetH = _sheetExpanded ? screenH * 0.52 : screenH * 0.25;

    return Scaffold(
      body: Stack(
        children: [
          // Camera background — DDP-inspired gradient or picked image
          Positioned.fill(
            child: _pickedBytes != null
                ? Image.memory(
                    _pickedBytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _DDPBackground(),
                  )
                : _DDPBackground(),
          ),
          // Status bar
          SafeArea(
            child: Column(
              children: [
                const AppStatusBar(dark: true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.camera_alt_rounded,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 5),
                          Text('Seoul Lens',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: kMint.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(children: [
                          const Icon(Icons.verified_rounded,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('Seoul Open Data',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // AR scan frame
          Center(
            child: AnimatedBuilder(
              animation: _scanCtrl,
              builder: (_, __) => CustomPaint(
                size: const Size(220, 220),
                painter: _ScanFramePainter(
                    scanProgress: _scanCtrl.value),
              ),
            ),
          ),
          // AR detected label — only once a real result comes back
          if (_placeResult != null)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.38,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                      '${_placeResult!.nameEnglish} · ${_placeResult!.confidence}% confidence',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ),
          // Glassmorphism bottom sheet
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < -5) setState(() => _sheetExpanded = true);
                if (d.delta.dy > 5) setState(() => _sheetExpanded = false);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                height: sheetH,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                        color: kMint.withValues(alpha: 0.08),
                        blurRadius: 30,
                        offset: const Offset(0, -8)),
                  ],
                ),
                child: Column(
                  children: [
                    // Drag handle
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 10),
                      decoration: BoxDecoration(
                        color: kCardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: _pickedImage != null
                          ? _buildGeminiResult()
                          : _buildEmptyPrompt(),
                    ),
                                        const AppBottomNav(currentIndex: 2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// DDP background — night cityscape using gradients and shapes
class _DDPBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A0E1A),
            Color(0xFF0D1525),
            Color(0xFF0F1E30),
            Color(0xFF122040),
          ],
          stops: [0.0, 0.3, 0.6, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _DDPPainter(),
        child: Container(),
      ),
    );
  }
}

class _DDPPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Night sky stars
    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.6);
    final stars = [
      Offset(w * 0.12, h * 0.08),
      Offset(w * 0.28, h * 0.04),
      Offset(w * 0.45, h * 0.1),
      Offset(w * 0.62, h * 0.06),
      Offset(w * 0.78, h * 0.12),
      Offset(w * 0.88, h * 0.05),
      Offset(w * 0.95, h * 0.15),
      Offset(w * 0.05, h * 0.18),
      Offset(w * 0.35, h * 0.15),
    ];
    for (final s in stars) {
      canvas.drawCircle(s, 1.5, starPaint);
    }

    // DDP building — fluid curved silver structure
    final buildingPaint = Paint()
      ..color = const Color(0xFF1A2744)
      ..style = PaintingStyle.fill;

    // Main DDP curved body
    final ddpPath = Path();
    ddpPath.moveTo(w * 0.05, h * 0.72);
    ddpPath.quadraticBezierTo(w * 0.1, h * 0.45, w * 0.25, h * 0.42);
    ddpPath.quadraticBezierTo(w * 0.42, h * 0.38, w * 0.5, h * 0.44);
    ddpPath.quadraticBezierTo(w * 0.62, h * 0.52, w * 0.72, h * 0.48);
    ddpPath.quadraticBezierTo(w * 0.85, h * 0.42, w * 0.95, h * 0.55);
    ddpPath.lineTo(w * 0.95, h * 0.72);
    ddpPath.close();
    canvas.drawPath(ddpPath, buildingPaint);

    // Silver highlight on DDP curves
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    final highlight = Path();
    highlight.moveTo(w * 0.1, h * 0.50);
    highlight.quadraticBezierTo(w * 0.3, h * 0.42, w * 0.5, h * 0.48);
    highlight.quadraticBezierTo(w * 0.65, h * 0.52, w * 0.8, h * 0.47);
    highlight.quadraticBezierTo(w * 0.65, h * 0.54, w * 0.5, h * 0.52);
    highlight.quadraticBezierTo(w * 0.3, h * 0.48, w * 0.1, h * 0.55);
    highlight.close();
    canvas.drawPath(highlight, highlightPaint);

    // Building windows / LED strips
    final ledPaint = Paint()
      ..color = kMint.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (double i = 0; i < 6; i++) {
      canvas.drawLine(
        Offset(w * (0.15 + i * 0.12), h * 0.58),
        Offset(w * (0.22 + i * 0.12), h * 0.55),
        ledPaint,
      );
    }

    // Yellow accent lights
    final yellowLed = Paint()
      ..color = kYellow.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (double i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(w * (0.20 + i * 0.15), h * 0.64),
        Offset(w * (0.28 + i * 0.15), h * 0.61),
        yellowLed,
      );
    }

    // Reflection on ground
    final reflectionPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          kMint.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, h * 0.7, w, h * 0.3));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.7, w, h * 0.3), reflectionPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanFramePainter extends CustomPainter {
  final double scanProgress;
  _ScanFramePainter({required this.scanProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kMint
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 28.0;
    final w = size.width;
    final h = size.height;

    // Corner brackets
    // Top-left
    canvas.drawLine(const Offset(0, corner), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(corner, 0), paint);
    // Top-right
    canvas.drawLine(Offset(w - corner, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, corner), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, h - corner), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(corner, h), paint);
    // Bottom-right
    canvas.drawLine(Offset(w - corner, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - corner), paint);

    // Scan line
    final scanY = h * scanProgress;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          kMint.withValues(alpha: 0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, scanY - 1, w, 3));
    canvas.drawLine(Offset(0, scanY), Offset(w, scanY), scanPaint..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter old) =>
      old.scanProgress != scanProgress;
}

/// A single full-width row in the landmark detail card. The value wraps to as
/// many lines as it needs (so subway directions never get clipped). When
/// [onTap] is set the row becomes a link (phone / website).
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLink = onTap != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: kMintLight,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: kMint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kSubtext,
                        letterSpacing: 0.5)),
                const SizedBox(height: 3),
                Text(value,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        height: 1.4,
                        color: isLink ? kMint : kInk,
                        fontWeight:
                            isLink ? FontWeight.w700 : FontWeight.w500,
                        decoration:
                            isLink ? TextDecoration.underline : null,
                        decorationColor: kMint)),
              ],
            ),
          ),
          if (isLink)
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 2),
              child: Icon(Icons.open_in_new_rounded, size: 15, color: kMint),
            ),
        ],
      ),
    );

    if (!isLink) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: row,
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: kMintLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kMint.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: kMint),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kInk),
            ),
          ],
        ),
      ),
    );
  }
}
