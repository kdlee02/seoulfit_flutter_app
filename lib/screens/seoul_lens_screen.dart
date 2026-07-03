import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/animations.dart';
import '../services/lens_service.dart';
import '../models/landmark_analysis.dart';

class SeoulLensScreen extends StatefulWidget {
  const SeoulLensScreen({super.key});

  @override
  State<SeoulLensScreen> createState() => _SeoulLensScreenState();
}

class _SeoulLensScreenState extends State<SeoulLensScreen>
    with TickerProviderStateMixin {
  late AnimationController _scanCtrl;
  late AnimationController _lockCtrl;
  final _picker = ImagePicker();
  final _lens = LensService();
  final _tts = FlutterTts();
  bool _isSpeaking = false;
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
    _lockCtrl = AnimationController(
      vsync: this,
      duration: Motion.base,
    );
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.5);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showMediaPicker());
  }

  /// Drives the AR frame: sweep while [scanning], else stop and play a one-shot
  /// "lock" pulse. Keeps the scanning animation off once a place is detected.
  void _setScanning(bool scanning) {
    if (scanning) {
      _lockCtrl.reset();
      if (!_scanCtrl.isAnimating) _scanCtrl.repeat(reverse: true);
    } else {
      _scanCtrl.stop();
      _lockCtrl.forward(from: 0);
    }
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
              content: Text('Camera access is needed.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13)),
              action:
                  const SnackBarAction(label: 'Settings', onPressed: openAppSettings),
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
        HapticFeedback.selectionClick();
        final bytes = await file.readAsBytes();
        setState(() {
          _pickedImage = file;
          _pickedBytes = bytes;
          _placeResult = null;
          _analyzeError = null;
        });
        _setScanning(true);
        await _analyzeWithBackend(file, bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't load that image.",
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
          _setScanning(false);
          setState(() => _analyzeError =
              "Couldn't recognize this place.\nTry another photo.");
        } else {
          // Lock the scan frame onto the detected landmark.
          _setScanning(false);
          HapticFeedback.mediumImpact();
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

  /// Wraps centered sheet content so it stays vertically centred yet remains
  /// scrollable — that's what lets the DraggableScrollableSheet be dragged even
  /// when the content is short.
  Widget _sheetScrollable(ScrollController sc, Widget child) {
    return LayoutBuilder(
      builder: (ctx, c) => SingleChildScrollView(
        controller: sc,
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildGeminiResult(ScrollController sc) {
    if (_isAnalyzing) {
      return _sheetScrollable(
        sc,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(color: kMint, strokeWidth: 3),
            ),
            const SizedBox(height: 14),
            Text('Identifying this landmark…',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: kSubtext)),
          ],
        ),
      );
    }
    if (_analyzeError != null) {
      return _sheetScrollable(
        sc,
        Padding(
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
        controller: sc,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeSlideIn(
              // Key by landmark so a new scan replays the reveal sequence.
              key: ValueKey('lens-head-${r.nameEnglish}'),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.nameEnglish,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: kInk)),
                            if (r.nameKorean.isNotEmpty)
                              Text(r.nameKorean,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12, color: kSubtext)),
                          ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: r.dataVerified ? kMintLight : kYellowLight,
                          borderRadius: BorderRadius.circular(50)),
                      child: Row(children: [
                        Icon(
                            r.dataVerified
                                ? Icons.verified_rounded
                                : Icons.auto_awesome_rounded,
                            size: 12,
                            color: r.dataVerified
                                ? kMint
                                : const Color(0xFFD97706)),
                        const SizedBox(width: 4),
                        Text(r.dataVerified ? 'Verified' : 'AI Guess',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: r.dataVerified
                                    ? kMint
                                    : const Color(0xFFD97706))),
                      ]),
                    ),
                  ]),
            ),
            FadeSlideIn(
              key: ValueKey('lens-details-${r.nameEnglish}'),
              delay: Motion.stagger,
              child: Builder(builder: (_) {
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
            })),
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
            FadeSlideIn(
              key: ValueKey('lens-audio-${r.nameEnglish}'),
              delay: Motion.stagger * 2,
              child: Container(
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
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_isSpeaking) {
                        await _tts.stop();
                        setState(() => _isSpeaking = false);
                      } else {
                        setState(() => _isSpeaking = true);
                        await _tts.speak(r.description);
                      }
                    },
                    icon: Icon(
                      _isSpeaking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      size: 16,
                    ),
                    label: Text(_isSpeaking ? 'Stop' : 'Play Audio'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isSpeaking ? Colors.redAccent : kMint,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50)),
                      textStyle: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 14),
            FadeSlideIn(
              key: ValueKey('lens-cta-${r.nameEnglish}'),
              delay: Motion.stagger * 3,
              child: SizedBox(
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
            )),
          ],
        ),
      );
    }
    return _sheetScrollable(
        sc, const CircularProgressIndicator(color: kMint));
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

  Widget _buildEmptyPrompt(ScrollController sc) {
    return _sheetScrollable(
      sc,
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
    _lockCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          // AR scan frame — sweeps while scanning, locks onto a detected place.
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_scanCtrl, _lockCtrl]),
              builder: (_, __) => CustomPaint(
                size: const Size(220, 220),
                painter: _ScanFramePainter(
                  scanProgress: _scanCtrl.value,
                  locked: _placeResult != null,
                  lockPulse: _lockCtrl.value,
                ),
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
                child: FadeSlideIn(
                  key: ValueKey('ar-label-${_placeResult!.nameEnglish}'),
                  offsetY: -8,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _placeResult!.nameEnglish,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        _ConfidenceRing(
                          key: ValueKey('conf-${_placeResult!.nameEnglish}'),
                          value: _placeResult!.confidence,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Glassmorphism bottom sheet — native drag/snap with inner scroll.
          DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.24,
            maxChildSize: 0.9,
            snap: true,
            snapSizes: const [0.24, 0.5, 0.9],
            builder: (ctx, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
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
                          ? _buildGeminiResult(scrollController)
                          : _buildEmptyPrompt(scrollController),
                    ),
                  ],
                ),
              );
            },
          ),
          // Fixed bottom nav — sits above the sheet so it stays tappable.
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AppBottomNav(currentIndex: 2),
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

  /// True once a landmark is detected: corners go solid/thicker, the sweep line
  /// disappears, and [lockPulse] (0→1) plays a one-shot settle.
  final bool locked;
  final double lockPulse;

  _ScanFramePainter({
    required this.scanProgress,
    this.locked = false,
    this.lockPulse = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final color = locked ? kSuccess : kMint;
    // Lock pulse: corners briefly thicken then settle.
    final pulse = locked ? (1 - lockPulse) : 0.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = (locked ? 3.5 : 2.5) + pulse * 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final corner = locked ? 34.0 : 28.0;
    final w = size.width;
    final h = size.height;

    // Corner brackets
    // Top-left
    canvas.drawLine(Offset(0, corner), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(corner, 0), paint);
    // Top-right
    canvas.drawLine(Offset(w - corner, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, corner), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, h - corner), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(corner, h), paint);
    // Bottom-right
    canvas.drawLine(Offset(w - corner, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - corner), paint);

    if (locked) {
      // Expanding ring flash on lock, fading out.
      if (lockPulse < 1) {
        final ring = Paint()
          ..color = kSuccess.withValues(alpha: 0.5 * (1 - lockPulse))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(w / 2, h / 2),
              width: w * (0.7 + lockPulse * 0.4),
              height: h * (0.7 + lockPulse * 0.4),
            ),
            const Radius.circular(16),
          ),
          ring,
        );
      }
      return;
    }

    // Scan line (only while scanning)
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
      old.scanProgress != scanProgress ||
      old.locked != locked ||
      old.lockPulse != lockPulse;
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

/// Compact ring showing detection confidence (0–100). Animates the arc up on
/// first build; the number counts up via the shared [CountUp] (reduced-motion
/// safe). Used on the AR "detected" label over the camera image.
class _ConfidenceRing extends StatelessWidget {
  final int value;
  static const double size = 34;
  const _ConfidenceRing({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (value.clamp(0, 100)) / 100),
            duration: Motion.slow,
            curve: Motion.enter,
            builder: (_, v, __) => SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(kMint),
              ),
            ),
          ),
          CountUp(
            value: value,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ],
      ),
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
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
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
