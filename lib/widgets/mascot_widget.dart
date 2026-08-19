import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'animations.dart';

enum MascotVariant { full, chip, loading }

class MascotWidget extends StatefulWidget {
  final double size;
  final MascotVariant variant;

  const MascotWidget({
    super.key,
    this.size = 120,
    this.variant = MascotVariant.full,
  });

  @override
  State<MascotWidget> createState() => _MascotWidgetState();
}

class _MascotWidgetState extends State<MascotWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _float;
  bool _floating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Slightly slower, gentler breath than the original 2s bob.
      duration: const Duration(milliseconds: 2600),
    );
    _float = Tween(begin: 0.0, end: 6.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the platform reduced-motion setting: hold the mascot still
    // instead of looping forever.
    final shouldFloat = !Motion.reduced(context);
    if (shouldFloat && !_floating) {
      _floating = true;
      _controller.repeat(reverse: true);
    } else if (!shouldFloat && _floating) {
      _floating = false;
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.variant == MascotVariant.chip) return _buildChip();

    final mascot = AnimatedBuilder(
      animation: _float,
      builder: (ctx, _) => Transform.translate(
        offset: Offset(0, -_float.value),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/images/seoulfit_mascot.png',
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
              ),
              if (widget.variant == MascotVariant.loading)
                Positioned(
                  bottom: 0,
                  child: _LoadingDots(),
                ),
            ],
          ),
        ),
      ),
    );

    // Spring pop-in the first time the mascot appears. Loading variant skips
    // the pop so the dots read as immediate feedback.
    if (widget.variant == MascotVariant.loading || Motion.reduced(context)) {
      return mascot;
    }
    return _PopIn(child: mascot);
  }

  Widget _buildChip() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kYellowLight,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: kYellow, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/seoulfit_mascot.png',
            width: 22,
            height: 22,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 6),
          const Text(
            'SeoulFit Buddy',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// One-shot spring scale-in used when the mascot first mounts.
class _PopIn extends StatefulWidget {
  final Widget child;
  const _PopIn({required this.child});

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.slow)..forward();
  late final Animation<double> _scale = Tween(begin: 0.7, end: 1.0).animate(
    CurvedAnimation(parent: _c, curve: Motion.spring),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final t = (_ctrl.value + delay) % 1.0;
            final scale = t < 0.5 ? 0.6 + t * 0.8 : 1.0 - (t - 0.5) * 0.8;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8 * scale.clamp(0.6, 1.0),
              height: 8 * scale.clamp(0.6, 1.0),
              decoration: BoxDecoration(
                color: kMint.withValues(alpha: 0.6 + 0.4 * scale.clamp(0.0, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
