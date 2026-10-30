import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Luxury Showroom Barcode / QR Tag Scanner with torch, camera toggle, and manual tag entry fallback.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, this.title = 'Scan Jewellery Tag'});
  final String title;
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _ctrl = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _emit(String raw) {
    if (_done || raw.trim().isEmpty) return;
    _done = true;
    Navigator.pop(context, raw.trim().toUpperCase());
  }

  Future<void> _manual() async {
    final tc = TextEditingController();
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Enter Article Tag Manually', style: T.display(22)),
          const SizedBox(height: 6),
          Text('Type the printed jewellery tag or barcode code exactly as shown on the tray.', style: T.body(12.5, color: Pal.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: tc,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: T.mono(16, w: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: 'Enter tag or barcode',
              prefixIcon: Icon(Icons.sell_outlined),
            ),
            onSubmitted: (s) => Navigator.pop(ctx, s),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Pal.teal),
            onPressed: () => Navigator.pop(ctx, tc.text),
            child: const Text('Lookup Tag'),
          ),
        ]),
      ),
    );
    if (v != null && v.trim().isNotEmpty) _emit(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.obsidian,
      appBar: AppBar(
        backgroundColor: Pal.obsidian,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title, style: T.display(18.5, color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Toggle Torch',
            icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: _torch ? Pal.goldSoft : Colors.white),
            onPressed: () async {
              await _ctrl.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
          IconButton(
            tooltip: 'Switch Camera',
            icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
            onPressed: _ctrl.switchCamera,
          ),
          TextButton(
            onPressed: _manual,
            child: Text('Manual', style: T.body(13.5, color: Pal.goldSoft, w: FontWeight.w700)),
          ),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _ctrl,
          onDetect: (cap) {
            for (final b in cap.barcodes) {
              final v = b.rawValue;
              if (v != null && v.isNotEmpty) {
                _emit(v);
                break;
              }
            }
          },
          errorBuilder: (_, err, __) => Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.videocam_off_outlined, color: Pal.goldSoft, size: 28),
                ),
                const SizedBox(height: 14),
                Text('Camera Feed Unavailable', style: T.display(20, color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  err.errorDetails?.message ?? 'Camera permission is disabled or unsupported in this browser.',
                  textAlign: TextAlign.center,
                  style: T.body(13, color: Colors.white70),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Pal.goldBright, foregroundColor: Pal.obsidian),
                  onPressed: _manual,
                  icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                  label: const Text('Enter Tag Code Manually'),
                ),
              ]),
            ),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 268,
              height: 176,
              decoration: BoxDecoration(
                border: Border.all(color: Pal.goldBright, width: 2),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: Pal.goldBright.withValues(alpha: 0.25), blurRadius: 24),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 42,
          child: Column(children: [
            const EnterpriseBadge('HUID / QR / Code-128 Ready', icon: Icons.qr_code_scanner_rounded),
            const SizedBox(height: 10),
            Text(
              'Align the ornament string tag inside the gold frame',
              textAlign: TextAlign.center,
              style: T.body(13, color: Colors.white70),
            ),
          ]),
        ),
      ]),
    );
  }
}
