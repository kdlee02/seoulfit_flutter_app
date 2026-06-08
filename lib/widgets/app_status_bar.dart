import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppStatusBar extends StatelessWidget {
  final bool dark;
  const AppStatusBar({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : kInk;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '9:41',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: -0.3,
            ),
          ),
          Row(
            children: [
              _WifiIcon(color: color),
              const SizedBox(width: 6),
              _BatteryIcon(color: color),
            ],
          ),
        ],
      ),
    );
  }
}

class _WifiIcon extends StatelessWidget {
  final Color color;
  const _WifiIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(16, 12),
      painter: _WifiPainter(color: color),
    );
  }
}

class _WifiPainter extends CustomPainter {
  final Color color;
  _WifiPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height;

    canvas.drawCircle(Offset(cx, cy), 2, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
    canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy), width: 8, height: 8), -3.14, 3.14, false, paint);
    canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy), width: 14, height: 14), -3.14, 3.14, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BatteryIcon extends StatelessWidget {
  final Color color;
  const _BatteryIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 25,
      height: 12,
      child: CustomPaint(
        painter: _BatteryPainter(color: color),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final Color color;
  _BatteryPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 1, size.width - 4, size.height - 2),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(rrect, paint..style = PaintingStyle.stroke..strokeWidth = 1.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 3, (size.width - 8) * 0.75, size.height - 6),
        const Radius.circular(1),
      ),
      paint..style = PaintingStyle.fill,
    );
    final tipPaint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 3.5, 4, 3, size.height - 8),
        const Radius.circular(1),
      ),
      tipPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}