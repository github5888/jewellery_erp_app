import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Row(children: [
      Icon(
        error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
        size: 18,
        color: error ? Colors.white : Pal.goldSoft,
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ]),
    backgroundColor: error ? Pal.danger : Pal.ink,
  ));
}

/// Crisp warm-ivory luxury card with subtle sand-gold border & soft elevation.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = 16,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Pal.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? Pal.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1A140E),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
  }
}

/// Deep Royal Espresso-Onyx card with 24K Champagne Gold shimmer & hairline border.
class LuxuryHeroCard extends StatelessWidget {
  const LuxuryHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 22,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF281E12), Pal.ink, Color(0xFF0E0A06)],
        ),
        border: Border.all(color: Pal.goldBright.withValues(alpha: 0.36), width: 1),
        boxShadow: [
          BoxShadow(
            color: Pal.ink.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(children: [
          Positioned(
            right: -36,
            top: -36,
            child: IgnorePointer(
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Pal.goldBright.withValues(alpha: 0.22),
                      Pal.goldBright.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ]),
      ),
    );
  }
}

/// Shimmering 24K Metallic Royal Gold CTA button for flagship actions (Sign In, Checkout).
class RoyalGoldButton extends StatelessWidget {
  const RoyalGoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: enabled
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE7C664), Color(0xFFC8992A), Color(0xFFA27310)],
              )
            : null,
        color: enabled ? null : Pal.lineStrong.withValues(alpha: 0.4),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Pal.goldBright.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.3, color: Pal.ink),
                    )
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: Pal.ink),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.body(14.8, color: Pal.ink, w: FontWeight.w800),
                        ),
                      ),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Overflow-proof 2-column grid that sizes each row intrinsically to fit text at any system font scale.
class ResponsiveGrid2 extends StatelessWidget {
  const ResponsiveGrid2({
    super.key,
    required this.children,
    this.spacing = 10,
  });
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      if (i > 0) rows.add(SizedBox(height: spacing));
      final first = children[i];
      final second = i + 1 < children.length ? children[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: first),
              SizedBox(width: spacing),
              Expanded(child: second ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

/// Tracked uppercase micro-badge (`ENTERPRISE`, `FINE 999`, `MFA VERIFIED`).
class EnterpriseBadge extends StatelessWidget {
  const EnterpriseBadge(
    this.text, {
    super.key,
    this.icon,
    this.dark = true,
  });
  final String text;
  final IconData? icon;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? Pal.goldBright.withValues(alpha: 0.14) : Pal.goldWash;
    final border = dark ? Pal.goldBright.withValues(alpha: 0.38) : Pal.goldBorder;
    final fg = dark ? Pal.goldSoft : Pal.goldDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.caps(9.5, color: fg, letterSpacing: 1.05),
          ),
        ),
      ]),
    );
  }
}

/// Overflow-safe executive KPI card in Royal Gold & Ivory.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.accent = Pal.goldDeep,
    this.accentWash = Pal.goldWash,
    this.onTap,
  });
  final String label;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color accent;
  final Color accentWash;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            if (icon != null) ...[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentWash,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.caps(9.8, color: Pal.muted, letterSpacing: 0.7),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.display(19, w: FontWeight.w600),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body(11.5, color: Pal.muted, w: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

/// Structured 3-column jewellery weight breakdown (Gross / Stone / Net Metal + Fine 999).
class WeightBreakdownBar extends StatelessWidget {
  const WeightBreakdownBar({
    super.key,
    required this.grossGrams,
    required this.stoneGrams,
    required this.netGrams,
    this.fineGramsValue,
  });
  final String grossGrams;
  final String stoneGrams;
  final String netGrams;
  final String? fineGramsValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Pal.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pal.line),
      ),
      child: Column(children: [
        Row(children: [
          _col('GROSS WT', grams(grossGrams)),
          Container(width: 1, height: 28, color: Pal.line),
          _col('LESS / STONE', grams(stoneGrams)),
          Container(width: 1, height: 28, color: Pal.line),
          _col('NET METAL', grams(netGrams), highlight: true),
        ]),
        if (fineGramsValue != null &&
            fineGramsValue!.isNotEmpty &&
            fineGramsValue != '0' &&
            fineGramsValue != '0.000000') ...[
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.verified_rounded, size: 14, color: Pal.gold),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Fine 999 Pure Equivalent',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.body(12, color: Pal.textSoft, w: FontWeight.w700),
              ),
            ),
            Text(fineGrams(fineGramsValue), style: T.mono(12.5, color: Pal.goldDeep, w: FontWeight.w700)),
          ]),
        ],
      ]),
    );
  }

  Widget _col(String title, String val, {bool highlight = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caps(9.5, color: Pal.muted, letterSpacing: 0.6)),
            const SizedBox(height: 3),
            Text(
              val,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.mono(
                12.5,
                w: highlight ? FontWeight.w700 : FontWeight.w600,
                color: highlight ? Pal.ink : Pal.textSoft,
              ),
            ),
          ]),
        ),
      );
}

/// Horizontal scrollable pill tabs in Royal Onyx & Gold.
class PillTabs<TValue> extends StatelessWidget {
  const PillTabs({
    super.key,
    this.items,
    this.tabs,
    this.selected,
    this.value,
    required this.onChanged,
  });
  final List<(TValue, String, IconData?)>? items;
  final List<(TValue, String)>? tabs;
  final TValue? selected;
  final TValue? value;
  final ValueChanged<TValue> onChanged;

  @override
  Widget build(BuildContext context) {
    final resolved = <(TValue, String, IconData?)>[
      if (items != null) ...items!,
      if (items == null && tabs != null)
        for (final t in tabs!) (t.$1, t.$2, null),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Pal.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Pal.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < resolved.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _tab(resolved[i].$1, resolved[i].$2, resolved[i].$3),
          ],
        ]),
      ),
    );
  }

  Widget _tab(TValue itemVal, String label, IconData? icon) {
    final activeVal = selected ?? value;
    final active = itemVal == activeVal;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: active
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFC59436), Color(0xFF96661A)],
              )
            : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: Pal.gold.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(itemVal),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: active ? Colors.white : Pal.goldDeep),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: T.body(
                  12.3,
                  w: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? Colors.white : Pal.textSoft,
                ),
              ),
            ]),
          ),
        ),
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
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Row(children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.caps(10.8, color: Pal.goldDeep, letterSpacing: 0.9),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ]),
      );
}

enum Tone { ok, warn, info, bad, danger, neutral, gold, violet }

Tone toneFor(String status) {
  final s = status.toUpperCase();
  if ([
    'CONFIRMED',
    'RECEIVED',
    'SETTLED',
    'DELIVERED',
    'IN_VAULT',
    'IN_STOCK',
    'AVAILABLE',
    'ACTIVE',
    'PAID',
    'COMPLETED',
    'RECONCILED',
    'POSTED',
    'PUBLISHED',
    'APPROVED',
    'VERIFIED',
    'GRANTED',
    'PASSED',
    'BALANCED',
    'SENT',
    'ELIGIBLE',
  ].contains(s)) {
    return Tone.ok;
  }
  if ([
    'PENDING',
    'IN_PROCESS',
    'IN_PROGRESS',
    'IN_TRANSIT',
    'DISPATCHED',
    'ASSAYED',
    'OPEN',
    'PARTIAL',
    'ISSUED',
    'ON_APPROVAL',
    'READY_TO_POST',
    'SUBMITTED',
    'REQUESTED',
    'QUEUED',
    'CLOSING',
    'RESERVED',
  ].contains(s)) {
    return Tone.warn;
  }
  if ([
    'RETURN',
    'RETURNED',
    'DEBIT',
    'DEBIT_NOTE',
    'CREDIT',
    'CREDIT_NOTE',
    'EINVOICE',
    'EWAY_BILL',
    'SUPPLIER',
    'KARIGAR',
    'REFINER',
  ].contains(s)) {
    return Tone.info;
  }
  if ([
    'DRAFT',
    'CLOSED',
    'ARCHIVED',
  ].contains(s)) {
    return Tone.neutral;
  }
  if ([
    'CUSTOMER',
    'VALID',
  ].contains(s)) {
    return Tone.gold;
  }
  if ([
    'SOLD',
    'CANCELLED',
    'VOID',
    'VOIDED',
    'FAILED',
    'REJECTED',
    'BLOCKED',
    'REVOKED',
    'SUSPENDED',
    'EXPIRED',
    'FAILED_QUARANTINE',
    'INELIGIBLE',
  ].contains(s)) {
    return Tone.bad;
  }
  if (['PLATFORM_SUPPORT'].contains(s)) return Tone.violet;
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
      Tone.ok => (const Color(0xFFE6F5EC), const Color(0xFF1D7A46)),
      Tone.warn => (const Color(0xFFFDF0D8), const Color(0xFFB46910)),
      Tone.info => (const Color(0xFFEBF1FD), const Color(0xFF28559A)),
      Tone.bad || Tone.danger => (Pal.dangerWash, Pal.danger),
      Tone.gold => (Pal.goldWash, Pal.goldDeep),
      Tone.violet => (Pal.violetWash, Pal.violet),
      Tone.neutral => (const Color(0xFFEEECE6), const Color(0xFF5A5449)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        statusLabel(text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: T.body(11.4, w: FontWeight.w700, color: fg),
      ),
    );
  }
}

class Chip2 extends StatelessWidget {
  const Chip2(
    this.text, {
    super.key,
    this.icon,
    this.mono = false,
    this.gold = true,
  });
  final String text;
  final IconData? icon;
  final bool mono;
  final bool gold;
  @override
  Widget build(BuildContext context) {
    final bg = gold ? Pal.goldWash : Pal.surfaceAlt;
    final border = gold ? Pal.goldBorder : Pal.line;
    final fg = gold ? Pal.goldDeep : Pal.textSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono
                ? T.mono(11.5, w: FontWeight.w700, color: fg)
                : T.body(11.5, w: FontWeight.w700, color: fg),
          ),
        ),
      ]),
    );
  }
}

class MonoTag extends StatelessWidget {
  const MonoTag(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Pal.surfaceAlt,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Pal.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Pal.muted),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.mono(11.5, color: Pal.textSoft, w: FontWeight.w600),
            ),
          ),
        ]),
      );
}

class KeyValue extends StatelessWidget {
  const KeyValue(
    this.k,
    this.v, {
    super.key,
    this.strong = false,
    this.mono = false,
    this.valueColor,
  });
  final String k;
  final String v;
  final bool strong;
  final bool mono;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              k,
              style: T.body(
                13.2,
                color: strong ? Pal.text : Pal.muted,
                w: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: mono
                  ? T.mono(strong ? 13.8 : 12.8, w: FontWeight.w700, color: valueColor ?? Pal.text)
                  : T.body(
                      strong ? 14.5 : 13.5,
                      w: strong ? FontWeight.w800 : FontWeight.w700,
                      color: valueColor ?? Pal.text,
                    ),
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
            color: Color.lerp(Pal.line, Pal.surfaceAlt, _c.value),
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
  Widget build(BuildContext context) => Panel(
        color: Pal.dangerWash,
        borderColor: Pal.danger.withValues(alpha: 0.22),
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Pal.danger.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_off_rounded, color: Pal.danger, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: T.body(13.5, color: Pal.danger, w: FontWeight.w600),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(140, 40)),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Retry'),
            ),
          ],
        ]),
      );
}

class EmptyBlock extends StatelessWidget {
  const EmptyBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Pal.goldWash,
              shape: BoxShape.circle,
              border: Border.all(color: Pal.goldBorder),
            ),
            child: Icon(icon, size: 26, color: Pal.goldDeep),
          ),
          const SizedBox(height: 14),
          Text(title, style: T.display(18.5), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(body, style: T.body(13, color: Pal.muted), textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ] else if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
              child: Text(actionLabel!),
            ),
          ],
        ]),
      );
}

/// Exact `pos.hrpocket.in` website brand emblem:
/// Rounded 24K burnished-gold square badge (`#E5BD50` → `#B8860B`) containing a
/// crisp white faceted cut-diamond icon matching the live web portal 1:1.
class GemMark extends StatelessWidget {
  const GemMark({
    super.key,
    this.color,
    this.size,
    this.darkSurface = false,
    this.plainIconOnly = false,
  });
  final Color? color;
  final double? size;
  final bool darkSurface;
  final bool plainIconOnly;

  @override
  Widget build(BuildContext context) {
    final s = size ?? 38;
    if (plainIconOnly) {
      return SizedBox(
        width: s,
        height: s,
        child: CustomPaint(
          painter: _WebsiteDiamondPainter(color ?? Colors.white),
        ),
      );
    }
    final radius = BorderRadius.circular(s * 0.27);
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE7C45E), Color(0xFFCA9822), Color(0xFFB8860B)],
        ),
        border: Border.all(
          color: darkSurface
              ? const Color(0xFFF6DE96).withValues(alpha: 0.55)
              : const Color(0xFFD6AE43).withValues(alpha: 0.45),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8860B).withValues(alpha: darkSurface ? 0.34 : 0.22),
            blurRadius: s * 0.30,
            offset: Offset(0, s * 0.08),
          ),
        ],
      ),
      padding: EdgeInsets.all(s * 0.21),
      child: CustomPaint(
        painter: _WebsiteDiamondPainter(color ?? Colors.white),
      ),
    );
  }
}

/// Exact `pos.hrpocket.in` website header brand lockup:
/// `[Gold Diamond Square Logo]  Jewellery ERP [SAAS]` (+ optional tenant subtitle).
class WebsiteBrandLockup extends StatelessWidget {
  const WebsiteBrandLockup({
    super.key,
    this.badgeSize = 38,
    this.fontSize = 18.5,
    this.subtitle,
    this.darkSurface = true,
    this.centered = false,
  });

  final double badgeSize;
  final double fontSize;
  final String? subtitle;
  final bool darkSurface;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final titleColor = darkSurface ? Colors.white : Pal.ink;
    final subColor = darkSurface ? Colors.white.withValues(alpha: 0.72) : Pal.muted;
    final pillBg = darkSurface
        ? Pal.goldBright.withValues(alpha: 0.16)
        : const Color(0xFFFBF3DC);
    final pillBorder = darkSurface
        ? Pal.goldBright.withValues(alpha: 0.48)
        : const Color(0xFFE3C878);
    final pillFg = darkSurface ? Pal.goldSoft : Pal.goldDeep;

    return Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      children: [
        GemMark(size: badgeSize, darkSurface: darkSurface),
        const SizedBox(width: 11),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  Flexible(
                    child: Text(
                      'Jewellery ERP',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.body(fontSize, color: titleColor, w: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: pillBorder),
                    ),
                    child: Text(
                      'SAAS',
                      style: T.caps(9.2, color: pillFg, letterSpacing: 0.9),
                    ),
                  ),
                ],
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(12.2, color: subColor, w: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WebsiteDiamondPainter extends CustomPainter {
  const _WebsiteDiamondPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Exact 24x24 Lucide `Gem` cut-diamond geometry used on `pos.hrpocket.in`:
    // Outer silhouette: M6 3 h12 l4 6 -10 13 L2 9 Z
    // Girdle: M2 9 h20
    // Facets: M11 3 L8 9 L12 22 L16 9 L13 3
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;
    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, size.shortestSide * 0.095)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final outer = Path()
      ..moveTo(6 * sx, 3.2 * sy)
      ..lineTo(18 * sx, 3.2 * sy)
      ..lineTo(22 * sx, 9.2 * sy)
      ..lineTo(12 * sx, 21.6 * sy)
      ..lineTo(2 * sx, 9.2 * sy)
      ..close();

    final facets = Path()
      ..moveTo(10.6 * sx, 3.2 * sy)
      ..lineTo(8.0 * sx, 9.2 * sy)
      ..lineTo(12.0 * sx, 21.6 * sy)
      ..lineTo(16.0 * sx, 9.2 * sy)
      ..lineTo(13.4 * sx, 3.2 * sy);

    canvas.drawPath(outer, stroke);
    canvas.drawLine(p(2, 9.2), p(22, 9.2), stroke);
    canvas.drawPath(facets, stroke);
  }

  @override
  bool shouldRepaint(covariant _WebsiteDiamondPainter old) => old.color != color;
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Row(children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body(13, w: FontWeight.w700, color: Pal.textSoft),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Flexible(child: trailing!),
          ],
        ]),
      );
}

class KVRow extends StatelessWidget {
  const KVRow(
    this.k,
    this.v, {
    super.key,
    this.strong = false,
    this.bold = false,
    this.mono = false,
    this.valueColor,
  });
  final String k;
  final String v;
  final bool strong;
  final bool bold;
  final bool mono;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => KeyValue(
        k,
        v,
        strong: strong || bold,
        mono: mono,
        valueColor: valueColor,
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, this.tone});
  final String text;
  final Tone? tone;

  @override
  Widget build(BuildContext context) => StatusPill(text, tone: tone);
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Pal.dangerWash,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pal.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: Pal.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: T.body(12.8, color: Pal.danger, w: FontWeight.w600),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}

class GoldButton extends StatelessWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.compact = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Pal.gold,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
        child: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      );
    }
    return RoyalGoldButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      busy: busy,
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hasHeader = (title != null && title!.isNotEmpty) ||
        (subtitle != null && subtitle!.isNotEmpty) ||
        trailing != null;
    if (!hasHeader) {
      return Panel(child: child);
    }
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null && title!.isNotEmpty)
                      Text(title!, style: T.display(17, w: FontWeight.w700)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      if (title != null && title!.isNotEmpty) const SizedBox(height: 2),
                      Text(subtitle!, style: T.body(12, color: Pal.muted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
