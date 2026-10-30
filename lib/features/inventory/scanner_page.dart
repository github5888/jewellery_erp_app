import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';

/// Full-screen barcode scanner. Pops with the scanned value.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, this.title = 'Scan barcode'});
  final String title;
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.qrCode],
  );
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(v.trim());
        return;
      }
    }
  }

  Future<void> _manual() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Pal.pearl,
        title: Text('Type the barcode', style: T.display(20)),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.characters),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Use this')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty && mounted) {
      _done = true;
      Navigator.of(context).pop(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final box = size.width * 0.74;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (ctx, err, child) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Camera access is needed to scan. Allow it in your phone settings, or type the barcode instead.',
                textAlign: TextAlign.center,
                style: T.body(15, color: Colors.white70),
              ),
            ),
          ),
        ),
        // Dimmed surround with a clear scan window.
        CustomPaint(painter: _Mask(box: box)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  _controller.toggleTorch();
                  setState(() => _torch = !_torch);
                },
                icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: Colors.white),
              ),
            ]),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.title, style: T.display(22, color: Colors.white)),
                const SizedBox(height: 6),
                Text('Hold the tag steady inside the frame', style: T.body(14, color: Colors.white70)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _manual,
                  child: Text('Type barcode instead', style: T.body(14.5, color: Pal.goldSoft, w: FontWeight.w800)),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Mask extends CustomPainter {
  _Mask({required this.box});
  final double box;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: box, height: box * 0.62);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rr)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.58));
    final corner = Paint()
      ..color = Pal.goldSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 26.0;
    void c(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx * l, 0), corner);
      canvas.drawLine(o, o + Offset(0, dy * l), corner);
    }

    c(rect.topLeft, 1, 1);
    c(rect.topRight, -1, 1);
    c(rect.bottomLeft, 1, -1);
    c(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _Mask old) => old.box != box;
}
