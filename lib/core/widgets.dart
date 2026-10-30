import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Pal.danger : Pal.ink,
  ));
}

/// Hairline-bordered surface. Flat on purpose: depth is reserved for the rate plate.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Pal.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Pal.line),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: T.body(14, w: FontWeight.w800, color: Pal.muted))),
          if (trailing != null) trailing!,
        ]),
      );
}

enum Tone { ok, warn, bad, neutral, gold }

Tone toneFor(String status) {
  final s = status.toUpperCase();
  if (['CONFIRMED', 'IN_VAULT', 'IN_STOCK', 'AVAILABLE', 'OPEN', 'ACTIVE', 'PAID', 'COMPLETED', 'RETURNED', 'POSTED', 'PUBLISHED', 'CONSUMED']
      .contains(s)) {
    return Tone.ok;
  }
  if (['RESERVED', 'PENDING', 'DRAFT', 'PARTIAL', 'ISSUED', 'ON_APPROVAL', 'READY_TO_POST', 'SUBMITTED', 'EXPIRED'].contains(s)) {
    return Tone.warn;
  }
  if (['SOLD', 'CANCELLED', 'VOID', 'VOIDED', 'FAILED', 'REJECTED', 'BLOCKED', 'REVOKED', 'SUSPENDED', 'CLOSED', 'RELEASED'].contains(s)) {
    return (s == 'CLOSED' || s == 'RELEASED') ? Tone.neutral : Tone.bad;
  }
  return Tone.neutral;
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.tone});
  final String text;
  final Tone? tone;
  @override
  Widget build(BuildContext context) {
    final t = tone ?? toneFor(text);
    final (bg, fg) = switch (t) {
      Tone.ok => (Pal.okWash, Pal.ok),
      Tone.warn => (Pal.warnWash, Pal.warn),
      Tone.bad => (Pal.dangerWash, Pal.danger),
      Tone.gold => (Pal.goldWash, Pal.gold),
      Tone.neutral => (const Color(0xFFEDEBE5), Pal.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(statusLabel(text), style: T.body(12, w: FontWeight.w800, color: fg)),
    );
  }
}

class Chip2 extends StatelessWidget {
  const Chip2(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Pal.goldWash,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: Pal.gold), const SizedBox(width: 4)],
          Text(text, style: T.body(12, w: FontWeight.w800, color: const Color(0xFF7A5A1E))),
        ]),
      );
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.k, this.v, {super.key, this.strong = false, this.valueColor});
  final String k;
  final String v;
  final bool strong;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(k, style: T.body(14, color: Pal.muted, w: strong ? FontWeight.w700 : FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: T.body(strong ? 16 : 14.5,
                  w: strong ? FontWeight.w800 : FontWeight.w700, color: valueColor ?? Pal.text),
            ),
          ),
        ]),
      );
}

class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 10});
  final double height;
  final double? width;
  final double radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(const Color(0xFFE9E7E0), const Color(0xFFF1F0EB), _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      );
}

class ErrorBlock extends StatelessWidget {
  const ErrorBlock(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Pal.dangerWash, shape: BoxShape.circle),
            child: const Icon(Icons.cloud_off_rounded, color: Pal.danger),
          ),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center, style: T.body(14.5, color: Pal.muted)),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
          ],
        ]),
      );
}

class EmptyBlock extends StatelessWidget {
  const EmptyBlock({super.key, required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 34, color: Pal.gold),
          const SizedBox(height: 12),
          Text(title, style: T.display(20), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(body, style: T.body(14, color: Pal.muted), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

/// Brilliant-cut mark, drawn in code so the app ships with no image assets.
class GemMark extends StatelessWidget {
  const GemMark({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GemPainter());
}

class _GemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    Offset pt(double radius, int i, double offsetDeg) {
      final a = (i * 45 + offsetDeg) * math.pi / 180;
      return c + Offset(math.cos(a), math.sin(a)) * radius;
    }

    final outer = List.generate(8, (i) => pt(r, i, 22.5));
    final inner = List.generate(8, (i) => pt(r * 0.52, i, 0));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..color = Pal.goldSoft;
    final fill = Paint()..color = Pal.goldSoft.withValues(alpha: 0.14);

    final op = Path()..addPolygon(outer, true);
    final ip = Path()..addPolygon(inner, true);
    canvas.drawPath(op, fill);
    canvas.drawPath(op, stroke);
    canvas.drawPath(ip, stroke);
    for (var i = 0; i < 8; i++) {
      canvas.drawLine(outer[i], inner[i], stroke);
      canvas.drawLine(outer[i], inner[(i + 7) % 8], stroke);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Label above an input, sentence case.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 7),
        child: Text(text, style: T.body(13, w: FontWeight.w700, color: Pal.muted)),
      );
}
